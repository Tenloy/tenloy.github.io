---
title: (六) dyld与Objc—_objc_init、map_images、load_images
date: 2021-10-21 10:20:00
urlname: dyld-objc.html
tags:
categories:
  - 编译链接与装载
---

## 一、前文回顾

上一篇[(六) Mach-O 文件的动态链接、库、Dyld(含dlopen)](https://tenloy.github.io/2021/09/27/compile-dynamic-link.html)，大概梳理了dyld的加载流程，这一次主要展开**“第八步 执行初始化方法”**，其是我们日常紧密接触的OBJC Runtime初始化启动的上文。

先简单回顾一下Runtime的初始化之前的流程：
1. 内核XNU加载Mach-O
2. 从XNU内核态将控制权转移到dyld用户态
3. dyld：
   1. 设置运行环境
   2. 实例化ImageLoader加载所需的动态库、并进行链接(符号绑定、重定位)。每个image对应一个ImageLoader实例
   3. 进行images的初始化：先初始化动态库，再初始化可执行文件。这步过程中，**Runtime会向dyld中注册回调函数。dyld会在每个image加载、初始化、移除时分别调用Runtime的回调函数：map_images、load_images、unmap_images**. 
   4. 最后找到主程序的入口main()函数并返回。

可以在程序中，通过符号断点的形式`Debug → breakpoints → create symbolic breakpoint`来看这几个函数的调用堆栈：

添加符号断点：

<img src="/images/compilelink/35.png" alt="35" style="zoom:90%;" />

load_images的调用堆栈(之一)：

<img src="/images/compilelink/31.png" alt="35" style="zoom:90%;" />

在进入 `libobjc` 之前，我们必须要先了解 OC 中类的底层结构，可以先阅读[下篇](https://tenloy.github.io/2021/10/11/runtime-data-structure.html)(如果已经熟悉，那略过)。

## 二、_objc_init()

通过方法的文档注释，可以大概了解它的作用：启动初始化，注册dyld中image相关的回调通知，由libSystem在库(image)的初始化之前调用。

### 2.1 _objc_init()源码实现

```c++
/**
* _objc_init
* Bootstrap initialization. Registers our image notifier with dyld.
* Called by libSystem BEFORE library initialization time
  */
  void _objc_init(void)
  {
    static bool initialized = false;
    if (initialized) return;
    initialized = true;
  
    // runtime环境的各种初始化
    environ_init();   // 环境变量初始化。读取影响运行时的环境变量。如果需要，还可以打印环境变量
    tls_init();       // 关于线程key的绑定，如线程的析构函数
    static_init();    // 运行C++静态构造函数
    runtime_init();
    exception_init(); // 初始化libobjc的异常处理系统，由map_images()调用。
  #if __OBJC2__
    cache_t::init();
  #endif
    // 初始化 trampoline machinery。通常这什么都不做，因为一切都是惰性初始化的，但对于某些进程，我们会主动加载 trampolines dylib。
    _imp_implementationWithBlock_init();
		
    // 注册dyld事件的监听，监听每个image(动态库、可执行文件)的加载
    _dyld_objc_notify_register(&map_images, load_images, unmap_image);

  	// runtime 监听到dyld中image加载后，调用 map_images 做解析和处理，至此，可执行文件中和动态库所有的符号（Class，Protocol，Selector，IMP，…）都已经按格式成功加载到内存中，被 runtime 所管理，在这之后，runtime 的那些方法（动态添加 Class、swizzle 等等才能生效）
    // 接下来 load_images 中调用 call_load_methods 方法，遍历所有加载进来的 Class，按继承层级依次调用 Class 的 +load 方法和其 Category 的 +load 方法

#if __OBJC2__
    didCallDyldNotifyRegister = true;
#endif
}
```

### 2.2 tls_init()

```c++
// 线程局部/本地存储(Thread Local Storage, TLS) 是一种存储持续期（storage duration），对象的存储是在线程开始时分配，线程结束时回收，每个线程有该对象自己的实例。
// 线程私有数据(Thread Specific Data, TSD)

// objc's key for pthread_getspecific
#if SUPPORT_DIRECT_THREAD_KEYS
#define _objc_pthread_key TLS_DIRECT_KEY
#else
static tls_key_t _objc_pthread_key;
#endif

/*
 tls init：线程本地存储的初始化。
 _objc_pthread_destroyspecific 是线程的销毁函数。以 TLS_DIRECT_KEY 为 Key，在线程的本地存储空间中保存线程对应对销毁函数。
 */
void tls_init(void)
{
#if SUPPORT_DIRECT_THREAD_KEYS
    pthread_key_init_np(TLS_DIRECT_KEY, &_objc_pthread_destroyspecific);
#else
    _objc_pthread_key = tls_create(&_objc_pthread_destroyspecific);
#endif
}
```

`pthread_key_init_np` 是属于 `libpthread` 库中的方法了

```c++
/*
 为静态键设置析构函数，因为它不是用pthread_key_create()创建的
 */
int pthread_key_init_np(int key, void (*destructor)(void *));

/*
 * 分配用于表示进程中线程特定数据的键，键对进程中的所有线程来说是全局的。
 * 创建线程特定数据时，所有线程最初都具有与该键关联的NULL值。
 * @param key 指向从进程中已分配的键
 * @param destructor 指向析构函数，destuctor的形参是线程与键关联的数据。在线程终止时调用该函数，以达到释放内存的目的
 * @return 成功返回0.其他任何返回值都表示出现了错误。如果出现下列任一情况，pthread_key_create()将失败并返回相应的值
       EAGAIN：key名称空间已用完
       ENOMEM：此进程中虚拟内存不足，无法创建新键
 */
int pthread_key_create(pthread_key_t *key, void (*destructor)(void *));
```

### 2.3 runtime_init()


```c++
namespace objc {
  // 主要用来为类统计分类、追加分类到类、清除分类数据、清除类数据。
  class UnattachedCategories : public ExplicitInitDenseMap<Class, category_list> {}
  static UnattachedCategories unattachedCategories; 
  // allocatedClasses 是已使用 objc_allocateClassPair allocated 过的所有类（和元类）的表
  static ExplicitInitDenseSet<Class> allocatedClasses;
}

void runtime_init(void)
{
    objc::unattachedCategories.init(32); // 初始化分类的存储容器, 是Map
    objc::allocatedClasses.init(); // 初始化类的存储容器，是Set
}
```

### 2.4 cache_t::init()

```c++
#include <kern/restartable.h>

// 描述用户空间的可恢复范围
typedef struct {
	mach_vm_address_t location;     // 指向可重启动section开头的指针
	unsigned short    length;       // 锚定在location的section的长度
	unsigned short    recovery_offs;// 应该用于恢复的初始位置的偏移量
	unsigned int      flags;
} task_restartable_range_t;

void cache_t::init()
{
#if HAVE_TASK_RESTARTABLE_RANGES
  // mach_msg_type_number_t 当前是 unsigned int 的别名，定义别名利于不同的平台做兼容
  mach_msg_type_number_t count = 0;
  // kern_return_t 当前是 int 的别名
  kern_return_t kr;

  // 统计objc_restartableRanges数组中location成员值不为空的task_restartable_range_t的数量
  while (objc_restartableRanges[count].location) {
      count++;
  }

  // 为当前任务注册一组可重启范围。Register a set of restartable ranges for the current task.
  kr = task_restartable_ranges_register(mach_task_self(),
                                        objc_restartableRanges, count);
  if (kr == KERN_SUCCESS) return;
	
  // 注册失败则停止运行
  _objc_fatal("task_restartable_ranges_register failed (result 0x%x: %s)",
              kr, mach_error_string(kr));
#endif // HAVE_TASK_RESTARTABLE_RANGES
}
```

全局搜索 `objc_restartableRanges` 可看到，在 `_collecting_in_critical` 函数中有看到有对其的遍历读取。

```c++
▼ void cache_t::insert(SEL sel, IMP imp, id receiver)
  /* 第一次申请或扩容；扩容时，会清空现有数据. 扩容系数不同平台有3/4、7/8 */
  ▼ void cache_t::reallocate(mask_t oldCapacity, mask_t newCapacity, bool freeOld);
  // 或 void cache_t::eraseNolock(const char *func); // 将整个缓存重置为未缓存查找
    /* 将指定的malloc的内存添加到稍后要释放的内存列表中。
       size用于收集的阈值。它不必精确地与块的大小相同。*/
    ▼ void cache_t::collect_free(bucket_t *data, mask_t capacity)
        /* 尝试释放累积的失效缓存. collectALot更努力地释放内存 */
      ▼ void cache_t::collectNolock(bool collectALot); 
          /* 用于判断当前是否可以对旧的方法缓存（扩容后的旧的方法缓存表）进行收集释放
             返回 true 表示objc_msgSend（或其他缓存读取器(cache reader)）当前正在缓存中查找，并
             且可能仍在使用某些garbage。返回 false 的话表示 garbage 中的 bucket_t 没有被在使用。
             即当前有其它线程正在读取使用我们的旧的方法缓存表时，此时不能对旧的方法缓存表进行内存释放*/
        ▼ static int _collecting_in_critical(void);  //(critical 危急的；临界的；关键的)
```

### 2.5 _dyld_objc_notify_register()

`_dyld_objc_notify_register` 函数仅供 objc runtime 使用，注册当 mapped、unmapped 和 initialized objc images 时要调用的处理程序。Dyld 将使用包含 `objc-image-info` section 的 images 数组回调 `mapped` 函数。

> 在iOS 13系统中，iOS将全面采用新的dyld 3以替代之前版本的dyld 2。dyld 3带来了可观的性能提升，减少了APP的启动时间。

在 dyld3 中，`_dyld_objc_notify_register` 函数的实现逻辑有一些改变，此处不再赘述了。

- map_images : dyld 将 image 加载进内存时 , 会触发该函数进行image的一些处理：如果是首次，初始化执行环境等，之后`_read_images`进行读取，进行类、元类、方法、协议、分类的一些加载。
- load_images : dyld 初始化 image 会触发该方法，进行+load的调用
- unmap_image : dyld 将 image 移除时 , 会触发该函数

## 三、map_images() 

```c++
/**
* Process the given images which are being mapped(映射、加载) in by dyld.
* Calls ABI-agnostic code after taking ABI-specific locks.
* Locking: write-locks runtimeLock
*/
void map_images(unsigned count, const char * const paths[],
           const struct mach_header * const mhdrs[])
{
    rwlock_writer_t lock(runtimeLock);
    return map_images_nolock(count, paths, mhdrs);
}
```

### 3.1 map_images_nolock()

```c++
/*
 * 处理由dyld映射的给定图像。
 * 执行所有的类注册和修复(或延迟查找丢失的超类等)，并调用+load方法。
 * Info[]是自底向上的顺序，即libobjc将在数组中比任何链接到libobjc的库更早。
 */
void map_images_nolock(unsigned mhCount, const char * const mhPaths[],
                  const struct mach_header * const mhdrs[])
{
    // 局部静态变量，表示第一次调用
    static bool firstTime = YES;
    
    // hList 是统计 mhdrs 中的每个 mach_header 对应的 header_info
    header_info *hList[mhCount];
    
    uint32_t hCount;
    size_t selrefCount = 0;

    // 如有必要，执行首次初始化。
    // 此函数在 ordinary library 初始化程序之前调用。
    // 延迟初始化，直到找到使用 objc 的图像
    
    // 如果是第一次加载，则准备初始化环境
    if (firstTime) {
        preopt_init();
    }

    // 开启 OBJC_PRINT_IMAGES 环境变量时，启动时则打印 images 数量。
    // 如：objc[10503]: IMAGES: processing 296 newly-mapped images... 
    if (PrintImages) {
        _objc_inform("IMAGES: processing %u newly-mapped images...\n", mhCount);
    }

    // Find all images with Objective-C metadata.
    hCount = 0;

    // 计算 class 的数量。根据总数调整各种表格的大小。
    
    int totalClasses = 0;
    int unoptimizedTotalClasses = 0;
    {
        uint32_t i = mhCount;
        while (i--) {
        
            // typedef struct mach_header_64 headerType;
            // 取得指定 image 的 header 指针
            const headerType *mhdr = (const headerType *)mhdrs[i];
            
            // 以 mdr 构建其 header_info，并添加到全局的 header 列表中（是一个链表，大概看源码到现在还是第一次看到链表的使用）。
            // 且通过 GETSECT(_getObjc2ClassList, classref_t const, "__objc_classlist"); 读取 __objc_classlist 区中的 class 数量添加到 totalClasses 中，
            // 以及未从 dyld shared cache 中找到 mhdr 的 header_info 时，添加 class 的数量到 unoptimizedTotalClasses 中。
            auto hi = addHeader(mhdr, mhPaths[i], totalClasses, unoptimizedTotalClasses);
            
            // 这里有两种情况下 hi 为空：
            // 1. mhdr 的 magic 不是既定的 MH_MAGIC、MH_MAGIC_64、MH_CIGAM、MH_CIGAM_64 中的任何一个
            // 2. 从 dyld shared cache 中找到了 mhdr 的 header_info，并且 isLoaded 为 true（）
            if (!hi) {
                // no objc data in this entry
                continue;
            }
            
            // #define MH_EXECUTE 0x2 /* demand paged executable file demand 分页可执行文件 */ 
            if (mhdr->filetype == MH_EXECUTE) {
                // Size some data structures based on main executable's size
                // 根据主要可执行文件的大小调整一些数据结构的大小

                size_t count;
                
                // ⬇️ GETSECT(_getObjc2SelectorRefs, SEL, "__objc_selrefs");
                // 获取 __objc_selrefs 区中的 SEL 的数量
                _getObjc2SelectorRefs(hi, &count);
                selrefCount += count;
                
                // GETSECT(_getObjc2MessageRefs, message_ref_t, "__objc_msgrefs"); 
                // struct message_ref_t {
                //     IMP imp;
                //     SEL sel;
                // };
                // ⬇️ 获取 __objc_msgrefs 区中的 message 数量
                _getObjc2MessageRefs(hi, &count);
                selrefCount += count;
...
            }
            
            hList[hCount++] = hi;
            
            if (PrintImages) {
                // 打印 image 信息
                // 如：objc[10565]: IMAGES: loading image for /usr/lib/system/libsystem_blocks.dylib (has class properties) (preoptimized)
                _objc_inform("IMAGES: loading image for %s%s%s%s%s\n", 
                             hi->fname(),
                             mhdr->filetype == MH_BUNDLE ? " (bundle)" : "",
                             hi->info()->isReplacement() ? " (replacement)" : "",
                             hi->info()->hasCategoryClassProperties() ? " (has class properties)" : "",
                             hi->info()->optimizedByDyld()?" (preoptimized)":"");
            }
        }
    }

    // ⬇️⬇️⬇️
    // Perform one-time runtime initialization that must be deferred until the executable itself is found. 
    // 执行 one-time runtime initialization，必须推迟到找到可执行文件本身。
    // This needs to be done before further initialization.
    // 这需要在进一步初始化之前完成。
    
    // The executable may not be present in this infoList if the executable does not contain
    // Objective-C code but Objective-C is dynamically loaded later.
    // 如果可执行文件不包含 Objective-C 代码但稍后动态加载 Objective-C，则该可执行文件可能不会出现在此 infoList 中。
    
    if (firstTime) {
        // 初始化 selector 表并注册内部使用的 selectors。
        sel_init(selrefCount);
        
        // ⬇️⬇️⬇️ 这里的 arr_init 函数超重要，可看到它内部做了三件事：
        // 1. 自动释放池的初始化（实际是在 TLS 中以 AUTORELEASE_POOL_KEY 为 KEY 写入 tls_dealloc 函数（自动释放池的销毁函数：内部所有 pages pop 并 free））
        // 2. SideTablesMap 初始化，也可理解为 SideTables 的初始化（为 SideTables 这个静态全局变量开辟空间）
        // 3. AssociationsManager 的初始化，即为全局使用的关联对象表开辟空间
        // void arr_init(void) 
        // {
        //     AutoreleasePoolPage::init();
        //     SideTablesMap.init();
        //     _objc_associations_init();
        // }
        
        arr_init();
        
...

// 这一段是在较低版本下 DYLD_MACOSX_VERSION_10_13 之前的版本中禁用 +initialize fork safety，大致看看即可
#if TARGET_OS_OSX
        // Disable +initialize fork safety if the app is too old (< 10.13).
        // Disable +initialize fork safety if the app has a
        //   __DATA,__objc_fork_ok section.

        if (dyld_get_program_sdk_version() < DYLD_MACOSX_VERSION_10_13) {
            DisableInitializeForkSafety = true;
            if (PrintInitializing) {
                _objc_inform("INITIALIZE: disabling +initialize fork "
                             "safety enforcement because the app is "
                             "too old (SDK version " SDK_FORMAT ")",
                             FORMAT_SDK(dyld_get_program_sdk_version()));
            }
        }

        for (uint32_t i = 0; i < hCount; i++) {
            auto hi = hList[i];
            auto mh = hi->mhdr();
            if (mh->filetype != MH_EXECUTE) continue;
            unsigned long size;
            if (getsectiondata(hi->mhdr(), "__DATA", "__objc_fork_ok", &size)) {
                DisableInitializeForkSafety = true;
                if (PrintInitializing) {
                    _objc_inform("INITIALIZE: disabling +initialize fork "
                                 "safety enforcement because the app has "
                                 "a __DATA,__objc_fork_ok section");
                }
            }
            break;  // assume only one MH_EXECUTE image
        }
#endif

    }
    
    // ⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️ 下面就来到了最核心的地方
    // 以 header_info *hList[mhCount] 数组中收集到的 images 的 header_info 为参，直接进行 image 的读取
    if (hCount > 0) {
        _read_images(hList, hCount, totalClasses, unoptimizedTotalClasses);
    }
    
    // 把开始时初始化的静态局部变量 firstTime 置为 NO
    firstTime = NO;
    
    // ⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️
    // _read_images 看完再看下面的 loadImageFuncs 函数  
    
    // Call image load funcs after everything is set up.
    // 一切设置完毕后调用 image 加载函数。
    for (auto func : loadImageFuncs) {
        for (uint32_t i = 0; i < mhCount; i++) {
            func(mhdrs[i]);
        }
    }
}
```
`map_images_nolock` 就是：

- 对 `const struct mach_header * const mhdrs[]` 参数的处理，把数组中的 `mach_header` 转换为 `header_info` 并存在 `header_info *hList[mhCount]` 数组中。
- 并统计 `totalClasses` 和 `unoptimizedTotalClasses` 的数量
- 然后调用下面的 `_read_images` 函数

> 在阅读_read_images()函数前，先来了解一下class在加载过程都有哪些状态，在objc中以怎样的数据结构来记录的。

### 3.2 class加载过程中的flag标志

当调用 runtime API 动态创建类的过程，包括三个步骤：

- 调用`Class objc_allocateClassPair(...)`构建类；
- 添加必要的成员变量、方法等元素；
- 调用`void objc_registerClassPair(Class cls)`注册类；

然而，runtime 从镜像（image）加载类的过程会更加精细，在加载类的不同阶段会被标记为不同的类型（还是`objc_class`结构体，只是`flags`不同），例如：

- **future class**（未来要解析的类，也称懒加载类）
  - named class（已确定名称类）：将`cls`标记为 named class，以`cls->mangledName()`类名为关键字添加到全局记录的`gdb_objc_realized_classes`哈希表中，表示 runtime 开始可以通过类名查找类（注意元类不需要添加）；
  - allocated class（已分配内存类）：将`cls`及其元类标记为 allocated class，并将两者均添加到全局记录的`allocatedClasses`哈希表中（无需关键字），表示已为类分配固定内存空间；
- **remapped class**（已重映射类）
- **realized class**（已认识/实现类）
- loaded class（已加载类）：已执行`load`方法的类
- initialized class（已初始化类）：已执行`initialize()`方法的类

> realized: adj. 已实现的; v. 意识到，认识到，理解；实现；把（概念等）具体表现出来.
>
> OC 类在被使用之前（譬如调用类方法），需要进行一系列的初始化，譬如：指定 `superclass`、指定 `isa` 指针、`attach categories` 等等；libobjc 在 runtime 阶段就可以做这些事情，但是有些过于浪费，更好的选择是懒处理，这一举措极大优化了程序的执行速度。而 runtime 把对类的惰性初始化过程称为「realize」。
>
> 利用已经被 `realize` 的类含有 `RW_REALIZED` 和 `RW_REALIZING` 标记的特点，可以为项目找出无用类；因为没有被使用的类，一定没有被 `realized`。

#### 3.2.1 class_rw_t->flags

`class_rw_t`的`flags`为可读写。其中比较重要的一些值定义列举如下，均以RW_为前缀。

```c++
// 该类是已实现/已认识/已初始化处理过的类
#define RW_REALIZED           (1<<31)
// 该类是尚未解析的unresolved future class
#define RW_FUTURE             (1<<30)
// 该类已经初始化。完成执行initialize()
#define RW_INITIALIZED        (1<<29)
// 该类正在初始化。正在执行initialize()
#define RW_INITIALIZING       (1<<28)
// class_rw_t->ro是class_ro_t的堆拷贝。此时类的class_rw_t->ro是可写入的，拷贝之前ro的内存区域锁死不可写入
#define RW_COPIED_RO          (1<<27)
// class allocated but not yet registered
#define RW_CONSTRUCTING       (1<<26)
// class allocated and registered
#define RW_CONSTRUCTED        (1<<25)
// 该类的load方法已经调用过
#define RW_LOADED             (1<<23)

#if !SUPPORT_NONPOINTER_ISA
// 该类的实例可能存在关联对象。默认编译选项下，无需定义该位，因为都可能有关联对象
#define RW_INSTANCES_HAVE_ASSOCIATED_OBJECTS (1<<22)
#endif

// 该类的实例具有特定的GC layout
#define RW_HAS_INSTANCE_SPECIFIC_LAYOUT      (1 << 21)
// 该类禁止在其实例上使用关联对象
#define RW_FORBIDS_ASSOCIATED_OBJECTS        (1<<20)
// 该类正在实现，但是未实现完成
#define RW_REALIZING          (1<<19)
```

#### 3.2.2 class_ro_t->flags

`class_ro_t`的`flags`成员为只读。其中比较重要的一些值定义列举如下，均以`RO_`为前缀。

```c++
// 类是元类
#define RO_META               (1<<0)
// 类是根类
#define RO_ROOT               (1<<1)
// 类有CXX构造/析构函数
#define RO_HAS_CXX_STRUCTORS  (1<<2)
// 类有实现load方法
// #define RO_HAS_LOAD_METHOD    (1<<3)
// 隐藏类
#define RO_HIDDEN             (1<<4)
// class has attribute(objc_exception): OBJC_EHTYPE_$_ThisClass is non-weak
#define RO_EXCEPTION          (1<<5)
// class has ro field for Swift metadata initializer callback
#define RO_HAS_SWIFT_INITIALIZER (1<<6)
// 类使用ARC选项编译
#define RO_IS_ARC             (1<<7)
// 类有CXX析构函数，但没有CXX构造函数
#define RO_HAS_CXX_DTOR_ONLY  (1<<8)
// class is not ARC but has ARC-style weak ivar layout 
#define RO_HAS_WEAK_WITHOUT_ARC (1<<9)
// 类禁止使用关联对象
#define RO_FORBIDS_ASSOCIATED_OBJECTS (1<<10)

// class is in an unloadable bundle - must never be set by compiler
#define RO_FROM_BUNDLE        (1<<29)
// class is unrealized future class - must never be set by compiler
#define RO_FUTURE             (1<<30)
// class is realized - must never be set by compiler
#define RO_REALIZED           (1<<31)
```

### 3.3 _read_images()

观看下面内容之前，如果对 OC 中 `Class`、`Category`、`Protocol`的实现结构(底层的结构体实现及成员变量)不熟悉，建议先看一下[Objc Runtime总结](https://tenloy.github.io/2020/10/28/runtime-data-structure.html)
```c++
// 对以 headerList 开头的链表中的 headers 进行初始处理
void _read_images(header_info **hList, uint32_t hCount, int totalClasses, int unoptimizedTotalClasses)
{
    header_info *hi;
    uint32_t hIndex;
    size_t count;
    size_t i;
    
    Class *resolvedFutureClasses = nil;
    size_t resolvedFutureClassCount = 0;
    
    // 静态局部变量，如果是第一次调用 _read_images 则 doneOnce 值为 NO
    static bool doneOnce;
    
    bool launchTime = NO;
    
    // 测量 image 加载步骤的持续时间
    // 对应 objc-env.h 中的 OPTION( PrintImageTimes, OBJC_PRINT_IMAGE_TIMES, "measure duration of image loading steps")
    TimeLogger ts(PrintImageTimes);

    // 加锁
    runtimeLock.assertLocked();

    // EACH_HEADER 是给下面的 for 循环使用的宏，遍历 hList 数组中的 header_info
#define EACH_HEADER \
    hIndex = 0;         \
    hIndex < hCount && (hi = hList[hIndex]); \
    hIndex++
```

#### 1. 是否是第一次加载

```c++
    // 1⃣️
    // 第一次调用 _read_images 时，doneOnce 值为 NO，会进入 if 执行里面的代码 
    if (!doneOnce) {
        // 把静态局部变量 doneOnce 置为 YES，之后调用 _read_images 都不会再进来
        // 第一次调用 _read_images 的时候，class、protocol、selector、category 都没有，
        // 需要创建容器来保存这些东西，此 if 内部，最后是创建一张存 class 的表。
        doneOnce = YES;
        
        launchTime = YES;

    // 这一段是在低版本（swifit3 之前、OS X 10.11 之前）下禁用 non-pointer isa 时的一些打印信息，
    // 为了减少我们的理解负担，这里直接进行了删除，想要学习的同学可以去看一下源码
    ...
        
        // OPTION( DisableTaggedPointers, OBJC_DISABLE_TAGGED_POINTERS, "disable tagged pointer optimization of NSNumber et al.")
        // 禁用 NSNumber 等的 Tagged Pointers 优化时
        if (DisableTaggedPointers) {
            // 内部直接把 Tagged Pointers 用到的 mask 全部置为 0
            disableTaggedPointers();
        }
        
        // OPTION( DisableTaggedPointerObfuscation, OBJC_DISABLE_TAG_OBFUSCATION, "disable obfuscation of tagged pointers")
        // 可开启 OBJC_DISABLE_TAG_OBFUSCATION，禁用 Tagged Pointer 的混淆。
        
        // 随机初始化 objc_debug_taggedpointer_obfuscator。
        // tagged pointer obfuscator 旨在使攻击者在存在缓冲区溢出或其他对某些内存的写控制的情况下更难将特定对象构造为标记指针。
        // 在设置或检索有效载荷值（payload values）时， obfuscator 与 tagged pointers 进行异或。
        // 它们在第一次使用时充满了随机性。
        initializeTaggedPointerObfuscator();

        // OPTION( PrintConnecting, OBJC_PRINT_CLASS_SETUP, "log progress of class and category setup")
        // objc[26520]: CLASS: found 25031 classes during launch 在 objc-781 下在启动时有 25031 个类（包含所有的系统类和自定义类）
        
        if (PrintConnecting) {
            _objc_inform("CLASS: found %d classes during launch", totalClasses);
        }

        // namedClasses
        // Preoptimized classes don't go in this table.
        // 4/3 is NXMapTable's load factor
        
        // isPreoptimized 如果我们有一个有效的优化共享缓存（valid optimized shared cache），则返回 YES。
        // 然后是不管三目运算符返回的是 unoptimizedTotalClasses 还是 totalClasses，它都会和后面的 4 / 3 相乘，
        // 注意是 4 / 3
        int namedClassesSize = (isPreoptimized() ? unoptimizedTotalClasses : totalClasses) * 4 / 3;
        
        // gdb_objc_realized_classes 是一张全局的哈希表，虽然名字中有 realized，但是它的名字其实是一个误称，
        // 实际上它存放的是不在 dyld shared cache 中的 class，无论该 class 是否 realized。
        gdb_objc_realized_classes = NXCreateMapTable(NXStrValueMapPrototype, namedClassesSize);
        
        // 在 objc-781 下执行到这里时，会有如下打印:
        // objc[19881]: 0.04 ms: IMAGE TIMES: first time tasks
        // 这个过程花了 0.04 毫秒
        ts.log("IMAGE TIMES: first time tasks");
    }
```

#### 2. 修复预编译时 @selector 错乱问题

```c++
    // 注册并修正 selector references. Fix up @selector references
    //（其实就是把 image 的 __objc_selrefs 区中的 selector 放进全局的 selector 集合中，修改其中不一致的地址）
		// 也就是当 SEL *sels = _getObjc2SelectorRefs(hi, &count); 中的 SEL 和通过 SEL sel = sel_registerNameNoLock(name, isBundle); 注册返回的 SEL 不同时，就把 sels 中的 SEL 修正为 sel_registerNameNoLock 中返回的地址。
    static size_t UnfixedSelectors;
    {
        // 加锁 selLock
        mutex_locker_t lock(selLock);
        
        // 遍历 header_info **hList 中的 header_info
        for (EACH_HEADER) {
        
            // 如果指定的 hi 不需要预优化则跳过
            if (hi->hasPreoptimizedSelectors()) continue;
            
            // 根据 mhdr()->filetype 判断 image 是否是 MH_BUNDLE 类型
            bool isBundle = hi->isBundle();
            
            // GETSECT(_getObjc2SelectorRefs, SEL, "__objc_selrefs");
            // 获取 __objc_selrefs 区中的 SEL
            SEL *sels = _getObjc2SelectorRefs(hi, &count);
            
            // 记录数量
            UnfixedSelectors += count;
            
            // static objc::ExplicitInitDenseSet<const char *> namedSelectors;
            // 是一个静态全局 set，用来存放 Selector（名字，Selector 本身就是字符串）
            
            // 遍历把 sels 中的所有 selector 放进全局的 selector 集合中   
            for (i = 0; i < count; i++) {
            
                // sel_cname 函数内部实现是返回：(const char *)(void *)sel; 即把 SEL 强转为 char 类型
                const char *name = sel_cname(sels[i]);
                
                // 注册 SEL，并返回其地址
                SEL sel = sel_registerNameNoLock(name, isBundle);
                
                // 如果 SEL 地址发生变化，则把它设置为相同
                if (sels[i] != sel) {
                    sels[i] = sel;
                }
            }
            
        }
    }
    
    // 这里打印注册并修正 selector references 用的时间
    // 在 objc-781 下打印：objc[27056]: 0.44 ms: IMAGE TIMES: fix up selector references
    // 耗时 0.44 毫秒
    ts.log("IMAGE TIMES: fix up selector references");
```

#### 3. readClass()读取类信息，修复future classes

通过 readClass 读取出来类的信息，修复未解析的future classes.

```c++
    // Discover classes. Fix up unresolved future classes. Mark bundle classes.
    // 发现 classes。修复 unresolved future classes。标记 bundle classes。
    
    // Returns if any OS dylib has overridden its copy in the shared cache
    //
    // Exists in iPhoneOS 3.1 and later 
    // Exists in Mac OS X 10.10 and later
    bool hasDyldRoots = dyld_shared_cache_some_image_overridden();

    for (EACH_HEADER) {
        if (! mustReadClasses(hi, hasDyldRoots)) {
            // Image is sufficiently optimized that we need not call readClass()
            // Image 已充分优化，我们无需调用 readClass()
            continue;
        }

        // GETSECT(_getObjc2ClassList, classref_t const, "__objc_classlist");
        // 获取 __objc_classlist 区中的 classref_t
        
        // 从编译后的类列表中取出所有类，获取到的是一个 classref_t 类型的指针 
        // classref_t is unremapped class_t* ➡️ classref_t 是未重映射的 class_t 指针
        // typedef struct classref * classref_t; // classref_t 是 classref 结构体指针
        classref_t const *classlist = _getObjc2ClassList(hi, &count);

        bool headerIsBundle = hi->isBundle();
        bool headerIsPreoptimized = hi->hasPreoptimizedClasses();

        for (i = 0; i < count; i++) {
            Class cls = (Class)classlist[i];
            
            // 重点 ⚠️⚠️⚠️⚠️ 在这里：readClass。
            // 我们留在下面单独分析。
            Class newCls = readClass(cls, headerIsBundle, headerIsPreoptimized);

            if (newCls != cls  &&  newCls) {
                // 类被移动但未被删除。目前，这种情况只发生在新类解析未来类时。
                // 非惰性地实现下面的类
                
                // realloc 原型是 extern void *realloc(void *mem_address, unsigned int newsize);
                // 先判断当前的指针是否有足够的连续空间，如果有，扩大 mem_address 指向的地址，并且将 mem_address 返回，
                // 如果空间不够，先按照 newsize 指定的大小分配空间，将原有数据从头到尾拷贝到新分配的内存区域，
                // 而后释放原来 mem_address 所指内存区域（注意：原来指针是自动释放，不需要使用 free），
                // 同时返回新分配的内存区域的首地址，即重新分配存储器块的地址。
                
                resolvedFutureClasses = (Class *)realloc(resolvedFutureClasses, (resolvedFutureClassCount+1) * sizeof(Class));
                resolvedFutureClasses[resolvedFutureClassCount++] = newCls;
            }
        }
    }

    // 这里打印发现 classes 用的时间
    // 在 objc-781 下打印：objc[56474]: 3.17 ms: IMAGE TIMES: discover classes
    // 耗时 3.17 毫秒（和前面的 0.44 毫秒比，多出不少）
    ts.log("IMAGE TIMES: discover classes");
```

##### 1) future class的生成

`objc_class`的`isFuture()`函数，用于判断类是否为 future class。future class 对理解类的加载过程有重要作用。

首先看 **future class 是如何生成的** — `addFutureNamedClass()`

```c++
/* 
 安装cls作为类结构，用于命名类(如果之后出现)。 
 将传入的 cls 参数，配置为类名为 name的 future class
 */
static void addFutureNamedClass(const char *name, Class cls)
{
    void *old;
		
    // 1. 分配 cls 所需的 class_rw_t、class_ro_t 的内存空间；
    class_rw_t *rw = (class_rw_t *)calloc(sizeof(class_rw_t), 1);
    class_ro_t *ro = (class_ro_t *)calloc(sizeof(class_ro_t), 1);
    // 2. 将 cls 的类名置为 name；
    ro->name = strdupIfMutable(name);
    // 3. 将 class_rw_t 的 RO_FUTURE 位置为1，RO_FUTURE 等于 RW_FUTURE；
    rw->ro = ro;
    cls->setData(rw);
    cls->data()->flags = RO_FUTURE; 
		// 4. 以 name 为关键字(key)，将 cls 添加到一个全局的哈希表 futureNamedClasses；
    old = NXMapKeyCopyingInsert(futureNamedClasses(), name, cls);
    assert(!old);
}

static NXMapTable *future_named_class_map = nil;
/* 返回一个map，key为 classname, value 为 unrealized future classes(Class实例)*/
static NXMapTable *futureNamedClasses()
{
    runtimeLock.assertLocked();
    
    if (future_named_class_map) return future_named_class_map;

    // future_named_class_map is big enough for CF’s classes and a few others
    future_named_class_map = 
        NXCreateMapTable(NXStrValueMapPrototype, 32);

    return future_named_class_map;
}

/*
 * 为给定的类名分配一个未解析的未来类 unresolved future class
 * 如果已经分配，则返回任何现有分配。
 */
Class _objc_allocateFutureClass(const char *name) {
    mutex_locker_t lock(runtimeLock);

    Class cls;
    NXMapTable *map = futureNamedClasses();

    if ((cls = (Class)NXMapGet(map, name))) {
        // 存在名为name的future class
        return cls;
    }
		// 分配用于保存objc_class的内存空间
    cls = _calloc_class(sizeof(objc_class));
  
    // 构建名为name的future class并全局记录到 futureNamedClasses 哈希表
    addFutureNamedClass(name, cls);

    return cls;
}

/* 
 Return the id of the named class.
 如果该类不存在，则返回一个未初始化的类结构，该结构将在类加载时使用。 
 */
Class objc_getFutureClass(const char *name) {
    Class cls;

    /* Class look_up_class(const char *name, 
              bool includeUnconnected __attribute__((unused)), 
              bool includeClassHandler __attribute__((unused))) // unconnected is OK，因为总有一天它会成为真正的class
    */
    cls = look_up_class(name, YES, NO);
    if (cls) {
        if (PrintFuture) {
            _objc_inform("FUTURE: found %p already in use for %s", 
                         (void*)cls, name);
        }
        return cls;
    }
    
    // 还没有名为name的class或future class。做一个。
    return _objc_allocateFutureClass(name);
}
```

调用链向上追溯到 `Class objc_getFutureClass`，该函数并没有在 runtime 源代码中被调用到。而用于从 `namedFutureClasses` 哈希表中获取 future class 的`popFutureClass(...)` 函数是有间接通过`readClass(...)`函数被广泛调用。因此，**构建 future class 的逻辑大多隐藏在 runtime 的内部实现中未公布，只有使用 future class 的逻辑是开源的**。

##### 2) future class的获取

 `popFutureNamedClass` 用于从 `futureNamedClasses` 哈希表中弹出类名为`name`的 future class，这是获取全局记录的 future class 的唯一入口。

```c++
/*
 Removes the named class from the unrealized future class list, because it has been realized.
 * Returns nil if the name is not used by a future class.
 */
static Class popFutureNamedClass(const char *name)
{
    runtimeLock.assertLocked();

    Class cls = nil;

    if (future_named_class_map) {
        cls = (Class)NXMapKeyFreeingRemove(future_named_class_map, name);
        if (cls && NXCountMapTable(future_named_class_map) == 0) {
            NXFreeMapTable(future_named_class_map);
            future_named_class_map = nil;
        }
    }

    return cls;
}
```

##### 3) future class的使用 — readClass

readClass 用于读取`cls`中的类数据，关键处理逻辑表述如下：

- 若 `futureNamedClasses` 哈希表中存在 `cls->mangledName()` 类名的 future class，则将`cls`重映射（remapping）到新的类 `newCls`（具体重映射过程在下面4小节中详细讨论），然后将 `newCls` 标记为 remapped class，以`cls`为关键字添加到全局记录的 `remappedClasses()` 哈希表中；
- 将`cls`标记为 named class，以 `cls->mangledName()` 类名为关键字添加到全局记录的 `gdb_objc_realized_classes` 哈希map中，表示 runtime 开始可以通过类名查找类（注意元类不需要添加）；
- 将`cls`及其元类标记为 allocated class，并将两者均添加到全局记录的 `allocatedClasses` 哈希set中，表示已为类分配固定内存空间；

> 注意：传入`readClass(...)`的`cls`参数是`Class`类型，而函数返回结果也是`Class`，为什么读取类信息是“从类中读取类信息”这样怪异的过程呢？
>
> 其实是因为`cls`参数来源于 runtime 未开源的、从镜像（image）中读取类的过程。该过程输出的`objc_class`存在特殊之处：要么输出 future class，要么输出正常(normal)类但是其`bits`指向的是`class_ro_t`结构体而非`class_rw_t`，之所以如此是因为从镜像读取的是编译时决议的静态数据，本来就应该保存在`class_ro_t`结构体中。

```c++
/***********************************************************************
* readClass
* Read a class and metaclass as written by a compiler.
* Returns the new class pointer. This could be: 
* - cls
* - nil  (cls has a missing weak-linked superclass)
* - something else (space for this class was reserved by a future class)
*
* Locking: runtimeLock acquired by map_images or objc_readClassPair
**********************************************************************/
Class readClass(Class cls, bool headerIsBundle, bool headerIsPreoptimized)
{
    const char *mangledName = cls->nonlazyMangledName();
    
    // 类的继承链上，存在既不是根类（RO_ROOT位为0）又没有超类的类，则为missingWeakSuperclass
    // 注意：这是唯一的向remappedClasses中添加nil值的入口
    if (missingWeakSuperclass(cls)) {
        addRemappedClass(cls, nil);
        cls->setSuperclass(nil);
        return nil;
    }
    
    // 兼容旧版本libobjc的配置，可忽略
    cls->fixupBackwardDeployingStableSwift();

    Class replacing = nil;
    if (mangledName != nullptr) {
        if (Class newCls = popFutureNamedClass(mangledName)) {
            // 这个name已经被分配为future class，全局记录。
            // 将cls的内容拷贝到newCls(也就是future class)中，保存future class的rw中的数据。将cls->data设置为rw->ro
            // 以cls为关键字将构建的newCls添加到全局记录的remappedClasses哈希表中

            if (newCls->isAnySwift()) {
                _objc_fatal("Can't complete future class request for '%s' "
                            "because the real class is too big.",
                            cls->nameForLogging());
            }

            class_rw_t *rw = newCls->data();
            const class_ro_t *old_ro = rw->ro();
            memcpy(newCls, cls, sizeof(objc_class));

            // Manually set address-discriminated ptrauthed fields
            // so that newCls gets the correct signatures.
            newCls->setSuperclass(cls->getSuperclass());
            newCls->initIsa(cls->getIsa());

            rw->set_ro((class_ro_t *)newCls->data());
            newCls->setData(rw);
            freeIfMutable((char *)old_ro->getName());
            free((void *)old_ro);

            addRemappedClass(cls, newCls);

            replacing = cls;
            cls = newCls;
        }
    }
    
    if (headerIsPreoptimized  &&  !replacing) {
        // class list built in shared cache
        // 已存在该类名的named class
        ASSERT(mangledName == nullptr || getClassExceptSomeSwift(mangledName));
    } else {
        if (mangledName) { // 一些Swift泛型类可以惰性地生成它们的名称
            // 将类添加到 named classes
            addNamedClass(cls, mangledName, replacing);
        } else {
            Class meta = cls->ISA();
            const class_ro_t *metaRO = meta->bits.safe_ro();
            ASSERT(metaRO->getNonMetaclass() && "Metaclass with lazy name must have a pointer to the corresponding nonmetaclass.");
            ASSERT(metaRO->getNonMetaclass() == cls && "Metaclass nonmetaclass pointer must equal the original class.");
        }
        // 将类添加到 allocated classes
        addClassTableEntry(cls);
    }

    // for future reference: shared cache never contains MH_BUNDLEs
    // 设置RO_FROM_BUNDLE位
    if (headerIsBundle) {
        cls->data()->flags |= RO_FROM_BUNDLE;
        cls->ISA()->data()->flags |= RO_FROM_BUNDLE;
    }
    
    return cls;
}
```

##### 4) future class小结

从上文`readClass(...)`代码`if (Class newCls = popFutureNamedClass(mangledName))`分支内`free((void *)old_ro)`语句，得出在`cls`映射到`newCls`过程中，完全丢弃了 future class 的`ro`数据。最后，结合以上所有代码，可以归纳以下结论：

- Future class 类的有效数据实际上仅有：类名和`rw`。`rw`中的数据作用也非常少，仅使用`flags`的`RO_FUTURE`（实际上就是`RW_FUTURE`）标记类是 future class；
- Future class 的作用是为指定类名的类，提前分配好内存空间，调用`readClass(...)`函数读取类时，才正式写入类的数据。 Future class 是用于支持类的懒加载机制；

#### 4. remapped(重新映射) classes

```c++    
    // Fix up remapped classes
    // Class list and nonlazy class list remain unremapped.
    // Class list 和 nonlazy class list 仍未映射。
    // Class refs and super refs are remapped for message dispatching.
    // Class refs 和 super refs 被重新映射为消息调度。
    
    // 主要是修复重映射 classes，!noClassesRemapped() 在这里为 false，所以一般走不进来，
    // 将未映射 class 和 super class 重映射，被 remap 的类都是非懒加载的类
    if (!noClassesRemapped()) {
        for (EACH_HEADER) {
            // GETSECT(_getObjc2ClassRefs, Class, "__objc_classrefs");
            // 获取 __objc_classrefs 区中的类引用
            Class *classrefs = _getObjc2ClassRefs(hi, &count);
            
            // 遍历 classrefs 中的类引用，如果类引用已被重新分配或者是被忽略的弱链接类，
            // 就将该类引用重新赋值为从重映射类表中取出新类
            for (i = 0; i < count; i++) {
                // Fix up a class ref, in case the class referenced has been reallocated or is an ignored weak-linked class.
                // 修复 class ref，以防所引用的类已 reallocated 或 is an ignored weak-linked class。
                remapClassRef(&classrefs[i]);
            }
            
            // fixme why doesn't test future1 catch the absence of this?
            // GETSECT(_getObjc2SuperRefs, Class, "__objc_superrefs");
            // 获取 __objc_superrefs 区中的父类引用
            classrefs = _getObjc2SuperRefs(hi, &count);
            
            for (i = 0; i < count; i++) {
                remapClassRef(&classrefs[i]);
            }
        }
    }

    // 这里打印修复重映射 classes 用的时间
    // 在 objc-781 下打印：objc[56474]: 0.00 ms: IMAGE TIMES: remap classes
    // 耗时 0 毫秒，即 Fix up remapped classes 并没有执行 
    ts.log("IMAGE TIMES: remap classes");

#if SUPPORT_FIXUP
...
#endif

    bool cacheSupportsProtocolRoots = sharedCacheSupportsProtocolRoots();
```

##### 1) future class 的重映射

在上面 `readClass()` 中有提到类的重映射，重映射的类被标记为 remapped class，并以映射前的类为关键字，添加到全局的`remappedClass`哈希表中。回顾`readClass()`函数中，类的重映射代码如下，关于处理过程的详细描述已注释到代码中：

```c++
    // 1. 若该类名已被标记为future class，则弹出该类名对应的future class 赋值给newCls
    if (Class newCls = popFutureNamedClass(mangledName)) {
        // 2. rw记录future class的rw
        class_rw_t *rw = newCls->data();
        // 3. future class的ro记为old_ro，后面释放其占用的内存空间并丢弃
        const class_ro_t *old_ro = rw->ro;
        // 4. 将cls中的数据拷贝到newCls，主要是要沿用cls的isa、superclass和cache数据
        memcpy(newCls, cls, sizeof(objc_class));
        // 5. rw记录cls的ro
        rw->ro = (class_ro_t *)newCls->data();
        // 6. 沿用future class的rw、cls的ro
        newCls->setData(rw);
        // 7. 释放future class的ro占用的空间
        freeIfMutable((char *)old_ro->name);
        free((void *)old_ro);
        
        // 8. 将newCls以cls为关键字添加到remappedClasses哈希表中
        addRemappedClass(cls, newCls);
        
        replacing = cls;
        cls = newCls;
    }
```

综合上面代码的详细注释，可知`cls`重映射到`newCls`后，`newCls`的数据保留了`cls`中的`superclass`、`cache`成员，但是`bits`中指向`class_rw_t`结构体地址的位域（`FAST_DATA_MASK`）指向了**新的`class_rw_t`结构体**。该结构体的`ro`指针指向`cls->data()`所指向的内存空间中保存的`class_ro_t`结构体，其他数据则是直接沿用 从`namedFutureClasses`哈希表中弹出的 future class 的`class_rw_t`结构体（通过future class 的`data()`方法返回）中数据。

> 注意：虽然`objc_class`的`data()`方法声明为返回`class_rw_t *`，但是究其本质，它只是返回了`objc_class`的`bits`成员的`FAST_DATA_MASK`标记的位域中保存的内存地址，该内存地址实际上可以保存任何类型的数据。在`Class readClass(Class cls, bool headerIsBundle, bool headerIsPreoptimized)`函数中，传入的`cls`所指向的`objc_class`结构体有其特殊之处：`cls`的`bits`成员的`FAST_DATA_MASK`位域，指向的内存空间保存的是`class_ro_t`结构体，并不是通常的`class_rw_t`。

##### 2) 通用类的重映射

通用的类重映射调用`static class remapClass(Class cls)`，注意当传入的`cls`类不在`remappedClasses`哈希表中时，直接返回`cls`本身；`static void remapClassRef(Class *clsref)`可对传入的`Class* clsref`重映射（改变`*clsref`的值），返回时`clsref`将 指向`*clsref`重映射后的类。类的重映射相关代码如下：

```c++
// 获取remappedClasses，保存已重映射的所有类的全局哈希表
static NXMapTable *remappedClasses(bool create)
{
    // 静态的全局哈希表，没有找到remove接口，只会无限扩张
    static NXMapTable *remapped_class_map = nil;

    runtimeLock.assertLocked();

    if (remapped_class_map) return remapped_class_map;
    if (!create) return nil;

    // remapped_class_map is big enough to hold CF’s classes and a few others
    INIT_ONCE_PTR(remapped_class_map, 
                  NXCreateMapTable(NXPtrValueMapPrototype, 32), 
                  NXFreeMapTable(v));

    return remapped_class_map;
}

// 将oldcls重映射得到的newcls，以oldcls为关键字插入到remappedClasses哈希表中
// 注意：从代码透露出来的信息是，remappedClasses中只保存 future class 重映射的类
static void addRemappedClass(Class oldcls, Class newcls)
{
    runtimeLock.assertLocked();

    if (PrintFuture) {
        _objc_inform("FUTURE: using %p instead of %p for %s", 
                     (void*)newcls, (void*)oldcls, oldcls->nameForLogging());
    }

    void *old;
    old = NXMapInsert(remappedClasses(YES), oldcls, newcls);
    assert(!old);
}

// 获取cls的重映射类
// 注意：当remappedClasses为空或哈希表中不存在`cls`关键字，是返回`cls`本身，否则返回`cls`重映射后的类
static Class remapClass(Class cls)
{
    runtimeLock.assertLocked();

    Class c2;

    if (!cls) return nil;

    NXMapTable *map = remappedClasses(NO);
    if (!map  ||  NXMapMember(map, cls, (void**)&c2) == NX_MAPNOTAKEY) {
        return cls;
    } else {
        return c2;
    }
}

// 对Class的指针的重映射，返回时传入的clsref将 指向*clsref重映射后的类
static void remapClassRef(Class *clsref)
{
    runtimeLock.assertLocked();

    Class newcls = remapClass(*clsref);    
    if (*clsref != newcls) *clsref = newcls;
}
```

##### 3) remap小结

最后归纳出以下结论：

- Future class 进行重映射后，会返回新的类，保存在`remappedClasses`全局哈希表中；
- 正常类重映射返回类本身；
- 重映射的真正的目的是支持类的懒加载，懒加载类暂存为 future class 只记录类名及 future class 属性，在调用`readClass`才正式载入类数据。

#### 5. 类中如果有协议，读取协议

```c++    
    // Discover protocols. Fix up protocol refs.
    // 发现 protocols，修正 protocol refs。
    for (EACH_HEADER) {
        extern objc_class OBJC_CLASS_$_Protocol;
        Class cls = (Class)&OBJC_CLASS_$_Protocol;
        ASSERT(cls);
        
        // 创建一个长度是 16 的 NXMapTable
        NXMapTable *protocol_map = protocols();
        bool isPreoptimized = hi->hasPreoptimizedProtocols();

        // Skip reading protocols if this is an image from the shared cache and we support roots
        // 如果这是来自 shared cache 的 image 并且我们 support roots，则跳过 reading protocols
        
        // Note, after launch we do need to walk the protocol as the protocol in the shared cache is marked with isCanonical()
        // and that may not be true if some non-shared cache binary was chosen as the canonical definition
        // 启动后，我们确实需要遍历协议，因为 shared cache 中的协议用 isCanonical() 标记，如果选择某些非共享缓存二进制文件作为规范定义，则可能不是这样
        
        if (launchTime && isPreoptimized && cacheSupportsProtocolRoots) {
            if (PrintProtocols) {
                _objc_inform("PROTOCOLS: Skipping reading protocols in image: %s", hi->fname());
            }
            continue;
        }

        bool isBundle = hi->isBundle();
        
        // GETSECT(_getObjc2ProtocolList, protocol_t * const, "__objc_protolist");
        // 获取 hi 的 __objc_protolist 区下的 protocol_t
        protocol_t * const *protolist = _getObjc2ProtocolList(hi, &count);
        
        for (i = 0; i < count; i++) {
            // Read a protocol as written by a compiler.
            readProtocol(protolist[i], cls, protocol_map, 
                         isPreoptimized, isBundle);
        }
    }
    
    // 这里打印发现并修正 protocols 用的时间
    // 在 objc-781 下打印：objc[56474]: 5.45 ms: IMAGE TIMES: discover protocols
    // 耗时 05.45 毫秒
    ts.log("IMAGE TIMES: discover protocols");
```

#### 6. 映射协议

```c++
    // Fix up @protocol references
    // Preoptimized images may have the right answer already but we don't know for sure.
    // Preoptimized images 可能已经有了正确的答案，但我们不确定。
    for (EACH_HEADER) {
        // At launch time, we know preoptimized image refs are pointing at the shared cache definition of a protocol.
        // 在启动时，我们知道 preoptimized image refs 指向协议的 shared cache 定义。
        // We can skip the check on launch, but have to visit @protocol refs for shared cache images loaded later.
        // 我们可以跳过启动时的检查，但必须访问 @protocol refs 以获取稍后加载的 shared cache images。
        
        if (launchTime && cacheSupportsProtocolRoots && hi->isPreoptimized())
            continue;
            
        // GETSECT(_getObjc2ProtocolRefs, protocol_t *, "__objc_protorefs");
        // 获取 hi 的 __objc_protorefs 区的 protocol_t
        protocol_t **protolist = _getObjc2ProtocolRefs(hi, &count);
        
        for (i = 0; i < count; i++) {
            // Fix up a protocol ref, in case the protocol referenced has been reallocated.
            // 修复 protocol ref，以防 protocol referenced 已重新分配。
            remapProtocolRef(&protolist[i]);
        }
    }
    
    // 这里打印 @protocol references 用的时间
    // 在 objc-781 下打印：objc[56474]: 0.00 ms: IMAGE TIMES: fix up @protocol references
    // 因为是第一次启动，则并不进行
    ts.log("IMAGE TIMES: fix up @protocol references");
```

#### 7. 加载分类

把 category 的数据追加到原类中去！很重要。

这里并不会执行，didInitialAttachCategories 是一个静态全局变量，默认是 false，对于启动时出现的 categories，discovery 被推迟到 `_dyld_objc_notify_register` 调用完成后的第一个 `load_images` 调用。所以这里 if 里面的 Discover categories 是不会执行的。

```c++    
    // Discover categories. 发现类别。
    // 仅在完成 initial category attachment 后才执行此操作。
    // 对于启动时出现的 categories，discovery 被推迟到 _dyld_objc_notify_register 调用完成后的第一个 load_images 调用。
    // 这里 if 里面的 category 数据加载是不会执行的。
    
    // didInitialAttachCategories 是一个静态全局变量，默认是 false，
    // static bool didInitialAttachCategories = false; 在load_images()函数体中，才会置为true

    if (didInitialAttachCategories) {
        for (EACH_HEADER) {
            load_categories_nolock(hi);
        }
    }

    // 这里打印 Discover categories. 用的时间
    // 在 objc-781 下打印：objc[56474]: 0.00 ms: IMAGE TIMES: discover categories
    // 对于启动时出现的 categories，discovery 被推迟到 _dyld_objc_notify_register 调用完成后的第一个 load_images 调用。
    // 所以这里 if 里面的 category 数据加载是不会执行的。
    ts.log("IMAGE TIMES: discover categories");
    
    // 当其他线程在该线程完成其修复(thread finishes its fixups)之前调用新的category代码时，category discovery必须延迟以避免潜在的竞争。 

    // +load 由 prepare_load_methods() 处理
```

#### 8. realize非懒加载类 — realized class

懒加载：类没有实现 +load 函数，在使用的第一次才会加载，当我们给这个类的发送消息时，如果是第一次，在消息查找的过程中就会判断这个类是否加载，没有加载就会加载这个类。懒加载类在首次调用方法的时候，才会去调用 `realizeClassWithoutSwift` 函数去进行加载。

非懒加载：类的内部实现了 +load 函数，类的加载就会提前。

```c++
    // Realize non-lazy classes (for +load methods and static instances)
    // 实现非懒加载类（为了+load调用、静态实例）
    for (EACH_HEADER) {
        // GETSECT(_getObjc2NonlazyClassList, classref_t const, "__objc_nlclslist");
        // 获取 hi 的 __objc_nlclslist 区中的非懒加载类（即实现了 +load 函数的类）
        classref_t const *classlist = _getObjc2NonlazyClassList(hi, &count);
        for (i = 0; i < count; i++) {
            // 重映射类， 获取正确的类指针
            Class cls = remapClass(classlist[i]);
            
            if (!cls) continue;
            
            // static void addClassTableEntry(Class cls, bool addMeta = true) { ... }
            // 将一个类添加到用来存储所有类的全局的 set 中（auto &set = objc::allocatedClasses.get();）。
            // 如果 addMeta 为 true（默认为 true），也自动添加类的元类到这个 set 中。
            // 这个类可以通过 shared cache 或 data segments 成为已知类，但不允许已经在 dynamic table 中。
            
            // allocatedClasses 是 objc 命名空间中的一个静态变量。
            // A table of all classes (and metaclasses) which have been allocated with objc_allocateClassPair.
            // 已使用 objc_allocateClassPair 分配空间的存储所有 classes（和 metaclasses）的 Set。
            // namespace objc {
            //     static ExplicitInitDenseSet<Class> allocatedClasses;
            // }
            
            // 先把 cls 放入 allocatedClasses 中，然后递归把 metaclass 放入 allocatedClasses 中
            addClassTableEntry(cls);
            
            // 判断 cls 是否是来自稳定的 Swift ABI 的 Swift 类
            if (cls->isSwiftStable()) {
                if (cls->swiftMetadataInitializer()) {
                    _objc_fatal("Swift class %s with a metadata initializer "
                                "is not allowed to be non-lazy",
                                cls->nameForLogging());
                }
                // fixme also disallow relocatable classes We can't disallow all Swift classes because of classes like Swift.__EmptyArrayStorage
                // 也禁止 relocatable classes 我们不能因为像 Swift.__EmptyArrayStorage 这样的类而禁止所有 Swift 类
            }
            
            // 实现 Swift 之外的 classes
            // 对类 cls 执行首次初始化，包括分配其读写数据。不执行任何 Swift 端初始化。返回类的真实类结构。
            
            // 大概是设置 ro rw 和一些标识位的过程，也包括递归实现父类（supercls = realizeClassWithoutSwift(remapClass(cls->superclass), nil);）
            // 和元类（metacls = realizeClassWithoutSwift(remapClass(cls->ISA()), nil);），
            // 然后更新 cls 的父类和元类（cls->superclass = supercls; cls->initClassIsa(metacls);），
            // 将 cls 连接到其父类的子类列表（addSubclass(supercls, cls);）（操作 class_rw_t 的 Class firstSubclass; 和 Class nextSiblingClass; 两个成员变量），
            // 修正 cls 的方法列表、协议列表和属性列表，
            // 以及最后的附加任何未完成的 categories（主要包含 method list、protocol list、property list）
            //（objc::unattachedCategories.attachToClass）。
            realizeClassWithoutSwift(cls, nil);
        }
    }
    
    // 这里打印 Realize non-lazy classes 用的时间
    // 在 objc-781 下打印：objc[56474]: 0.23 ms: IMAGE TIMES: realize non-lazy classes
    ts.log("IMAGE TIMES: realize non-lazy classes");
```

##### 1) realizeClassWithoutSwift()

调用`readClass(...)`读取类数据只是载入了类的`class_ro_t`静态数据，因此仍需要进一步配置`objc_class`的`class_rw_t`结构体的数据。这个过程为 class realizing，姑且称之为认识/实现类。具体包括：

- 配置`class_rw_t`的`RW_REALIZED`、`RW_REALIZING`位；
- 根据`class_ro_t`的`RO_META`位的值，配置`class_rw_t`的`version`；
- 因为静态载入的父类、元类有可能被重映射，因此要保证类的父类、元类完成class realizing；
- 配置`class_rw_t`的`superclass`；
- 初始化`objc_class`的`isa`指针；
- 配置`ivarLayout`、`instanceSize`、`instanceStart`。该步骤非常重要，新版本 runtime 支持 non-fragile instance variables，类的`instanceStart`、`instanceSize`会根据父类的`instanceSize`动态调整，且需要按 WORD 对齐（TODO：后续在独立的文章中详细介绍）；
- 配置`class_rw_t`的`RO_HAS_CXX_STRUCTORS`、`RO_HAS_CXX_DTOR_ONLY`、`RW_FORBIDS_ASSOCIATED_OBJECTS`；
- 添加子类/根类；
- 将`class_ro_t`中的基本方法列表、属性列表、协议列表，类的分类（category）中的方法列表等信息添加到`class_rw_t`中（TODO：后续在独立的文章中详细介绍）；

实现 class realizing 的代码主要在`static Class realizeClassWithoutSwift(Class cls)`函数中，只需要知道其大致过程即可。具体代码及注释如下：

```c++
/***********************************************************************
* 对类 cls 执行首次初始化，包括分配其读写(read-write)数据。
* 不执行任何 Swift 端初始化。
* 返回类的真实类结构(real class structure)
**********************************************************************/
static Class realizeClassWithoutSwift(Class cls, Class previously)
{
    runtimeLock.assertLocked();

    class_rw_t *rw;
    Class supercls;
    Class metacls;

    if (!cls) return nil;
    if (cls->isRealized()) {
        validateAlreadyRealizedClass(cls);
        return cls;
    }
    ASSERT(cls == remapClass(cls));  // // 传入的类必须存在于remappedClasses全局哈希表中

    // fixme verify class is not in an un-dlopened part of the shared cache?

    auto ro = (const class_ro_t *)cls->data();
    auto isMeta = ro->flags & RO_META;
    if (ro->flags & RO_FUTURE) {
        // 曾经是 a future class. 所以 rw data is already allocated.
        rw = cls->data();
        ro = cls->data()->ro();  // cls的rw指向class_rw_t结构体，ro指向class_ro_t结构体，维持原状
        ASSERT(!isMeta);
        cls->changeInfo(RW_REALIZED|RW_REALIZING, RW_FUTURE);
    } else {
        // 正常类(Normal class). 需要为rw分配内存，并将ro指针指向 传入的cls->data()所指向的内存空间
        rw = objc::zalloc<class_rw_t>();
        rw->set_ro(ro);
        rw->flags = RW_REALIZED|RW_REALIZING|isMeta;
        cls->setData(rw);
    }

    cls->cache.initializeToEmptyOrPreoptimizedInDisguise();

#if FAST_CACHE_META
    if (isMeta) cls->cache.setBit(FAST_CACHE_META);
#endif

    // Choose an index for this class.
    // Sets cls->instancesRequireRawIsa if indexes no more indexes are available
    cls->chooseClassArrayIndex();

    // 实现父类和元类，如果它们还没有实现。
    //   对于根类，这需要在上面设置RW_REALIZED之后完成。
    //   对于根元类，这需要在选择类索引之后完成。
    // (假设这些类都没有 Swift 内容，或者 Swift 的初始化程序(initializers)已经被调用)
    // (如果我们添加对 Swift 类的 ObjC 子类的支持，请修复这个假设是错误的。)
    supercls = realizeClassWithoutSwift(remapClass(cls->getSuperclass()), nil); // 父类 realizing
    metacls = realizeClassWithoutSwift(remapClass(cls->ISA()), nil);  // 元类 realizing

#if SUPPORT_NONPOINTER_ISA
    if (isMeta) {
        // 元类不需要来自non pointer ISA 的任何特性
        // 这允许在objc_retain/objc_release中为类提供一个faspath。
        cls->setInstancesRequireRawIsa(); // 配置RW_REQUIRES_RAW_ISA位。
    } else {
        // 为一些类或平台禁用 non-pointer isa
        bool instancesRequireRawIsa = cls->instancesRequireRawIsa();
        bool rawIsaIsInherited = false;
        static bool hackedDispatch = false;

        if (DisableNonpointerIsa) {
            // Non-pointer isa disabled by environment or app SDK version
            instancesRequireRawIsa = true;
        }
        else if (!hackedDispatch  &&  0 == strcmp(ro->getName(), "OS_object"))
        {
            // hack for libdispatch et al - isa also acts as vtable pointer
            hackedDispatch = true;
            instancesRequireRawIsa = true;
        }
        else if (supercls  &&  supercls->getSuperclass()  &&
                 supercls->instancesRequireRawIsa())
        {
            // 这也是通过addSubclass()传播的
            // 但是 nonpointer isa 设置需要更早.
            // 特殊情况：instancerequirerawisa不从根类传播到根元类
            instancesRequireRawIsa = true;
            rawIsaIsInherited = true;
        }
        
         // 配置RW_REQUIRES_RAW_ISA位
        if (instancesRequireRawIsa) {
            cls->setInstancesRequireRawIsaRecursively(rawIsaIsInherited);
        }
    }
#endif

    // 由于存在class remapping的可能性，因此需要更新父类及元类
    cls->setSuperclass(supercls);
    cls->initClassIsa(metacls);

    // 调整ivarLayout —— Reconcile(协调) instance variable offsets / layout
    // This may reallocate class_ro_t, updating our ro variable.
    if (supercls  &&  !isMeta) reconcileInstanceVariables(cls, supercls, ro);

    // 调整instanceSize —— Set fastInstanceSize if it wasn't set already.
    cls->setInstanceSize(ro->instanceSize);

    // Copy some flags from ro to rw
    if (ro->flags & RO_HAS_CXX_STRUCTORS) {
        cls->setHasCxxDtor();
        if (! (ro->flags & RO_HAS_CXX_DTOR_ONLY)) {
            cls->setHasCxxCtor();
        }
    }
    
    // 从 ro 或从父类传播关联对象禁止标志。
    if ((ro->flags & RO_FORBIDS_ASSOCIATED_OBJECTS) ||
        (supercls && supercls->forbidsAssociatedObjects()))
    {
        rw->flags |= RW_FORBIDS_ASSOCIATED_OBJECTS;
    }

    // 将此类连接到其父类的子类列表
    if (supercls) {
        addSubclass(supercls, cls);
    } else {
        addRootClass(cls);  // 添加父类
    }

    // rw中需要保存ro中的一些数据，例如ro中的基础方法列表、属性列表、协议列表
    // rw还需要载入分类的方法列表
    // Attach categories
    methodizeClass(cls, previously);  // methodize: vt. 使…有条理；为…定顺序

    return cls;
}
```

##### 2) methodizeClass

```c++
/***********************************************************************
* methodizeClass
* Fixes up cls's method list, protocol list, and property list.
* Attaches any outstanding categories.
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static void methodizeClass(Class cls, Class previously)
{
    runtimeLock.assertLocked();

    bool isMeta = cls->isMetaClass();
    auto rw = cls->data();
    auto ro = rw->ro();
    auto rwe = rw->ext();

    // 安装类自己实现的方法和属性。Install methods and properties that the class implements itself.
    // 将ro中的基本方法列表添加到rw的方法列表中
    method_list_t *list = ro->baseMethods();
    if (list) {
        prepareMethodLists(cls, &list, 1, YES, isBundleClass(cls), nullptr);
        if (rwe) rwe->methods.attachLists(&list, 1);
    }
    // 将ro中的属性列表添加到rw的属性列表中
    property_list_t *proplist = ro->baseProperties;
    if (rwe && proplist) {
        rwe->properties.attachLists(&proplist, 1);
    }
    // 将ro中的协议列表添加到rw的协议列表中
    protocol_list_t *protolist = ro->baseProtocols;
    if (rwe && protolist) {
        rwe->protocols.attachLists(&protolist, 1);
    }

    // 根元类特殊处理。
    // 根类可以获得额外的方法实现(如果它们还没有的话). 这些适用于类别替换(category replacements)之前。
    if (cls->isRootMetaclass()) {
        addMethod(cls, @selector(initialize), (IMP)&objc_noop_imp, "", NO);
    }

    // Attach categories. 将分类中的方法列表添加到rw的方法列表中
    if (previously) {
        if (isMeta) {
            objc::unattachedCategories.attachToClass(cls, previously,
                                                     ATTACH_METACLASS);
        } else {
            // 当类重定位时，带有类方法的类别categories可能会注册在类本身而不是元类metaclass上。告诉attachToClass去查找这些。
            objc::unattachedCategories.attachToClass(cls, previously,
                                                     ATTACH_CLASS_AND_METACLASS);
        }
    }
    objc::unattachedCategories.attachToClass(cls, cls,
                                             isMeta ? ATTACH_METACLASS : ATTACH_CLASS);
}
```

#### 9. 处理没有使用的类

第一次启动时并不会执行，我们也可以看到 `resolvedFutureClasses` 中并没有记录到需要执行 `realizeClassWithoutSwift` 的类

```c++    
    // Realize newly-resolved future classes, in case CF manipulates them
    // 实现 newly-resolved future classes，以防 CF 操作它们
    if (resolvedFutureClasses) {
        for (i = 0; i < resolvedFutureClassCount; i++) {
            Class cls = resolvedFutureClasses[i];
            if (cls->isSwiftStable()) {
                _objc_fatal("Swift class is not allowed to be future");
            }
            
            // 实现类
            realizeClassWithoutSwift(cls, nil);
            
            // 将此类及其所有子类标记为需要原始 isa 指针
            cls->setInstancesRequireRawIsaRecursively(false/*inherited*/);
        }
        free(resolvedFutureClasses);
    }
    
    // objc[56474]: 0.00 ms: IMAGE TIMES: realize future classes
    // 打印时间为 0.00 毫秒
    ts.log("IMAGE TIMES: realize future classes");
    
    // OPTION( DebugNonFragileIvars, OBJC_DEBUG_NONFRAGILE_IVARS, "capriciously rearrange non-fragile ivars")
    //（反复无常地重新排列非脆弱的 ivars）
    // 如果开启了 OBJC_DEBUG_NONFRAGILE_IVARS 这个环境变量，则会执行 realizeAllClasses() 函数，

    // Non-lazily realizes 所有已知 image 中所有未实现的类。(即对已知的 image 中的所有类：懒加载和非懒加载类全部进行实现)
    if (DebugNonFragileIvars) {
        realizeAllClasses();
    }

    // Print preoptimization statistics
    // 打印预优化统计信息
    
    // OPTION( PrintPreopt, OBJC_PRINT_PREOPTIMIZATION, "log preoptimization courtesy of dyld shared cache")
    // 日志预优化由 dyld shared cache 提供
```

#### 10. log输出

```c++    
    if (PrintPreopt) {
        // 一些 log 输出...
        ...
    }

#undef EACH_HEADER
}
```
## 四、load_images()

### 4.1 load_images()源码实现

```c++
/* 
 * 处理 dyld 映射的 images 中的 +load 
 */
void load_images(const char *path __unused, const struct mach_header *mh)
{
    // didInitialAttachCategories 标记加载分类的，默认值为 false，
    // didCallDyldNotifyRegister 标记 _dyld_objc_notify_register 是否调用完成
    if (!didInitialAttachCategories && didCallDyldNotifyRegister) {
        didInitialAttachCategories = true;
        loadAllCategories();
    }

    // 如果 mh 中不包含 +load 就直接不加锁 return（且 without taking locks）
    
    // hasLoadMethods 函数是根据 `headerType *mhdr` 的 `__objc_nlclslist` 区和 `__objc_nlcatlist` 区中是否有数据，来判断是否有 +load 函数要执行。(即是否包含非懒加载类和非懒加载分类) 
    if (!hasLoadMethods((const headerType *)mh)) return;

    // loadMethodLock 是一把递归互斥锁（加锁）
    recursive_mutex_locker_t lock(loadMethodLock);

    // 发现(Discover) +load 方法
    {   
        // runtimeLock 加锁
        mutex_locker_t lock2(runtimeLock);
        
        // 收集所有要调用的 +load 方法(Class、SuperClass、Category中的)
        prepare_load_methods((const headerType *)mh);
    }

    // Call +load methods (without runtimeLock - re-entrant)
    // 调用获取到的所有 +load 方法：从调用中，可以看到依次调用父类、子类、分类的load方法
    call_load_methods();
}
```

### 4.2 loadAllCategories() 分类加载

#### 4.2.1 loadAllCategories()

```c++
static void loadAllCategories() {
    mutex_locker_t lock(runtimeLock);

    for (auto *hi = FirstHeader; hi != NULL; hi = hi->getNext()) {
        load_categories_nolock(hi);
    }
}
```

#### 4.2.2 load_categories_nolock()

```c++
static void load_categories_nolock(header_info *hi) {
    bool hasClassProperties = hi->info()->hasCategoryClassProperties();

    size_t count;
    auto processCatlist = [&](category_t * const *catlist) {
        
        for (unsigned i = 0; i < count; i++) {
            category_t *cat = catlist[i];
            Class cls = remapClass(cat->cls);
            locstamped_category_t lc{cat, hi};

            if (!cls) {
                // Category's target class is missing (probably weak-linked).
                // Ignore the category.
                if (PrintConnecting) {
                    _objc_inform("CLASS: IGNORING category \?\?\?(%s) %p with "
                                 "missing weak-linked target class",
                                 cat->name, cat);
                }
                continue;
            }

            // Process this category.
            if (cls->isStubClass()) {
                // Stub(桩) classes永远不会实现(realized)。Stub classes在初始化之前不知道它们的元类，因此我们必须将带
                // 有类方法或属性的类别添加到Stub classes本身。methodizeClass() 将找到它们并将它们适当地添加到元类中。
                if (cat->instanceMethods ||
                    cat->protocols ||
                    cat->instanceProperties ||
                    cat->classMethods ||
                    cat->protocols ||
                    (hasClassProperties && cat->_classProperties))
                {
                    objc::unattachedCategories.addForClass(lc, cls);
                }
            } else {
                // 首先，将category注册到其目标类(target class)。
                // 然后，如果class is realized，则重建类的方法列表（等）。

                // 把分类中的，实例方法、协议、属性添加到类.
                if (cat->instanceMethods ||  
                    cat->protocols ||  
                    cat->instanceProperties)
                {
                    if (cls->isRealized()) {
                        attachCategories(cls, &lc, 1, ATTACH_EXISTING);
                    } else {
                        objc::unattachedCategories.addForClass(lc, cls);
                    }
                }

                // 把分类中的，类方法、协议添加到元类
                if (cat->classMethods  ||  
                    cat->protocols  ||  
                    (hasClassProperties && cat->_classProperties))
                {
                    if (cls->ISA()->isRealized()) {
                        attachCategories(cls->ISA(), &lc, 1, ATTACH_EXISTING | ATTACH_METACLASS);
                    } else {
                        objc::unattachedCategories.addForClass(lc, cls->ISA());
                    }
                }
            }
        }
    };

     // 对应
    // GETSECT(_getObjc2CategoryList, category_t *, "__objc_catlist");
    // GETSECT(_getObjc2CategoryList2, category_t * const, "__objc_catlist2");
    // _getObjc2CategoryList 取得 DATA 段 "__objc_catlist" section 中的 category 数据
    processCatlist(hi->catlist(&count));
    // _getObjc2CategoryList2 取得 DATA 段 "__objc_catlist2" section 中的 category 数据
    processCatlist(hi->catlist2(&count));
}
```

#### 4.2.3 attachCategories()

- 把所有Category的方法、属性、协议数据，合并到一个大数组中。后面参与编译的Category数据，会在数组的前面。
- 将合并后的分类数据(方法、属性、协议)，插入到类原来数据的前面。

```c++
// 将方法列表、属性和协议从categories附加到class。
static void
attachCategories(Class cls, const locstamped_category_t *cats_list, uint32_t cats_count, int flags)
{
    if (slowpath(PrintReplacedMethods)) {
        printReplacements(cls, cats_list, cats_count);
    }
    if (slowpath(PrintConnecting)) {
        _objc_inform("CLASS: attaching %d categories to%s class '%s'%s",
                     cats_count, (flags & ATTACH_EXISTING) ? " existing" : "",
                     cls->nameForLogging(), (flags & ATTACH_METACLASS) ? " (meta)" : "");
    }

    /*
     在发布期间，只有少数类的类别超过 64 个。
     这使用了一个小stack，避免了 malloc。
     Categories 必须以正确的顺序添加，即从后到前。为了通过分块(chunking)来做到这一点，我们从前到后迭代cats_list，向后构建本地缓冲区，
     并在块上调用attachLists。 attachLists将列表放在前面，因此最终结果按预期顺序排列。
     */
    constexpr uint32_t ATTACH_BUFSIZ = 64;
    method_list_t   *mlists[ATTACH_BUFSIZ];
    property_list_t *proplists[ATTACH_BUFSIZ];
    protocol_list_t *protolists[ATTACH_BUFSIZ];

    uint32_t mcount = 0;
    uint32_t propcount = 0;
    uint32_t protocount = 0;
    bool fromBundle = NO;
    bool isMeta = (flags & ATTACH_METACLASS);
    auto rwe = cls->data()->extAllocIfNeeded();

    for (uint32_t i = 0; i < cats_count; i++) {
        auto& entry = cats_list[i];

        method_list_t *mlist = entry.cat->methodsForMeta(isMeta);
        if (mlist) {
            if (mcount == ATTACH_BUFSIZ) {
                prepareMethodLists(cls, mlists, mcount, NO, fromBundle, __func__);
                rwe->methods.attachLists(mlists, mcount);
                mcount = 0;
            }
            mlists[ATTACH_BUFSIZ - ++mcount] = mlist;
            fromBundle |= entry.hi->isBundle();
        }

        property_list_t *proplist =
            entry.cat->propertiesForMeta(isMeta, entry.hi);
        if (proplist) {
            if (propcount == ATTACH_BUFSIZ) {
                rwe->properties.attachLists(proplists, propcount);
                propcount = 0;
            }
            proplists[ATTACH_BUFSIZ - ++propcount] = proplist;
        }

        protocol_list_t *protolist = entry.cat->protocolsForMeta(isMeta);
        if (protolist) {
            if (protocount == ATTACH_BUFSIZ) {
                rwe->protocols.attachLists(protolists, protocount);
                protocount = 0;
            }
            protolists[ATTACH_BUFSIZ - ++protocount] = protolist;
        }
    }

    if (mcount > 0) {
        prepareMethodLists(cls, mlists + ATTACH_BUFSIZ - mcount, mcount,
                           NO, fromBundle, __func__);
        rwe->methods.attachLists(mlists + ATTACH_BUFSIZ - mcount, mcount);
        if (flags & ATTACH_EXISTING) {
            flushCaches(cls, __func__, [](Class c){
                // constant caches have been dealt with in prepareMethodLists
                // if the class still is constant here, it's fine to keep
                return !c->cache.isConstantOptimizedCache();
            });
        }
    }

    rwe->properties.attachLists(proplists + ATTACH_BUFSIZ - propcount, propcount);

    rwe->protocols.attachLists(protolists + ATTACH_BUFSIZ - protocount, protocount);
}
```

### 4.3 hasLoadMethods()

根据 `headerType *mhdr` 的 `__objc_nlclslist` 区和 `__objc_nlcatlist` 区中是否有数据，来判断是否有 `+load` 函数要执行。

```c++
// Quick scan for +load methods that doesn't take a lock.
bool hasLoadMethods(const headerType *mhdr)
{
    size_t count;
    
    // GETSECT(_getObjc2NonlazyClassList, classref_t const, "__objc_nlclslist");
    // 1. 首先去看类列表中，有没有load方法
    // 读取__DATA段(Segment)中的__objc_nlclslist区(section)中的非懒加载类的列表。判断count是否大于1，大于1说明有load方法，直接返回。
    if (_getObjc2NonlazyClassList(mhdr, &count)  &&  count > 0) return true;
    
    // 2. 去所有的category中看，是否有load方法
    // GETSECT(_getObjc2NonlazyCategoryList, category_t * const, "__objc_nlcatlist");
    // 读取__DATA段中的__objc_nlcatlist区中非懒加载分类的列表
    if (_getObjc2NonlazyCategoryList(mhdr, &count)  &&  count > 0) return true;
    
    return false;
}
```

### 4.4 prepare_load_methods()

获取所有要调用的 +load 方法（父类、子类、分类）。

```c++
void prepare_load_methods(const headerType *mhdr)
{
    size_t count, i;

    runtimeLock.assertLocked();
    
    // GETSECT(_getObjc2NonlazyClassList, classref_t const, "__objc_nlclslist");
    // 获取所有 __objc_nlclslist 区的数据，即获取所有非懒加载类
    classref_t const *classlist = _getObjc2NonlazyClassList(mhdr, &count);
    
    // #define RW_LOADED (1<<23) // class +load has been called
    
    // 由于其构造方式，此列表始终首先处理 superclasses 的 +load 函数
    // 需要调用 +load 的 classes 列表
    // static struct loadable_class *loadable_classes = nil;

    // 遍历这些非懒加载类，并将其 +load 函数添加到 loadable_classes 数组中，优先添加其父类的 +load 方法，
    // 用于下面 call_load_methods 函数调用 
    for (i = 0; i < count; i++) {
        // 内部会递归调用，从传入的cls依次向上查找superClass，并调用add_class_to_loadable_list方法，将实现了load方法的类的：Class cls、IMP method收集
        // 父类、子类都通过该方法收集出来，父类们先被收集，即先被调用
        schedule_class_load(remapClass(classlist[i]));
    }

    // GETSECT(_getObjc2NonlazyCategoryList, category_t * const, "__objc_nlcatlist");
    // 获取所有 __objc_nlcatlist 区的数据，即获取所有非懒加载分类
    category_t * const *categorylist = _getObjc2NonlazyCategoryList(mhdr, &count);
    
    // 遍历这些分类
    for (i = 0; i < count; i++) {
        category_t *cat = categorylist[i];
        Class cls = remapClass(cat->cls);
        
        // weak-linked class：
        //   如果我们在一个库中使用新版本系统的一些特性API，但又想程序可以在低版本系统上运行，这个时候对这些符号使用弱引用就好。
        //   使用了弱引用之后，即使在版本较旧的环境下跑，也可以运行，只是相应的符号是NULL。
        //   有一点需要说明的是，如果一个framework没有为新加入的符号加入弱引用，那也不必担心，我们只要在链接时弱引用(weak link)整个framework就好
      
        // 如果没有找到分类所属的类就跳出当前循环，处理数组中的下一个分类
        if (!cls) continue;  // category for ignored weak-linked class
        
        if (cls->isSwiftStable()) {
            _objc_fatal("Swift class extensions and categories on Swift "
                        "classes are not allowed to have +load methods");
        }
        
        // 如果分类所属的类没有实现就先去实现
        realizeClassWithoutSwift(cls, nil);
        
        // 断言
        ASSERT(cls->ISA()->isRealized());
        
        // 需要调用 +load 的 categories 列表
        /* 
          static struct loadable_category *loadable_categories = nil;
          struct loadable_category {
              Category cat;  // may be nil
              IMP method;
          };
         */
        
        // 遍历这些分类，并将Category cat、IMP method收集到 loadable_categories 数组中保存
        add_category_to_loadable_list(cat);
    }
}
```

#### 4.4.1 schedule_class_load

```c++
// schedule_class_load 将其 +load 函数添加到 loadable_classes 数组中，优先添加其父类的 +load 方法。（用于后续 call_load_methods 函数调用）
static void schedule_class_load(Class cls)
{
    // 如果 cls 不存在则 return（下面有一个针对 superclass 的递归调用）
    if (!cls) return;
    
    // DEBUG 模式下的断言，cls 必须是实现过的（这个在 _read_images 中已经实现了）
    ASSERT(cls->isRealized());  // _read_images should realize
    
    // class +load has been called
    // #define RW_LOADED (1<<23)
    
    // RW_LOADED 是 class +load 已被调用的掩码
    if (cls->data()->flags & RW_LOADED) return;

    // Ensure superclass-first ordering
    // 优先处理 superclass 的 +load 函数
    schedule_class_load(cls->superclass);

    // static struct loadable_class *loadable_classes = nil;
    // struct loadable_class {
    //    Class cls;  // may be nil
    //    IMP method;
    // };
    
    // 将 cls 的 +load 函数添加到全局的 loadable_class 数组 loadable_classes 中，
    // loadable_class 结构体是用来保存类的 +load 函数的一个数据结构，其中 cls 是该类，method 则是 +load 函数的 IMP，
    // 这里也能看出 +load 函数是不走 OC 的消息转发机制的，它是直接通过 +load 函数的地址调用的！
    add_class_to_loadable_list(cls);
    
    // 将 RW_LOADED 设置到类的 Flags 中
    cls->setInfo(RW_LOADED); 
}

/*
 * Class cls has just become connected. Schedule it for +load if it implements a +load method.
 */
void add_class_to_loadable_list(Class cls)
{
    IMP method;

    loadMethodLock.assertLocked();

    // 1. 从 class 中获取 load 方法
    method = cls->getLoadMethod();
    if (!method) return;  // Don't bother if cls has no +load method
    
    if (PrintLoading) {
        _objc_inform("LOAD: class '%s' scheduled for +load", 
                     cls->nameForLogging());
    }
    
    // 2. 判断当前 loadable_classes 这个数组是否已经被全部占用
    if (loadable_classes_used == loadable_classes_allocated) {
        loadable_classes_allocated = loadable_classes_allocated*2 + 16;
        // 3. 在当前数组的基础上扩大数组的大小：realloc
        loadable_classes = (struct loadable_class *)
            realloc(loadable_classes,
                              loadable_classes_allocated *
                              sizeof(struct loadable_class));
    }
    
    // 4. 把传入的 class 以及对应的方法的实现IMP加到列表中
    loadable_classes[loadable_classes_used].cls = cls;
    loadable_classes[loadable_classes_used].method = method;
    loadable_classes_used++;
}
```

### 4.5 call_load_methods()

`+load` 函数的调用顺序：父类 -> 子类 -> 分类。

```c++
/**
 * Call all pending class and category +load methods.
 * Class +load methods are called superclass-first. 
 * Category +load methods are not called until after the parent class's +load.
 */
void call_load_methods(void)
{
    static bool loading = NO;
    bool more_categories;
    
    // 加锁
    loadMethodLock.assertLocked();

    // Re-entrant calls do nothing; the outermost call will finish the job.
    // 重入调用什么都不做；最外层的调用将完成工作。
    
    // 如果正在 loading 则 return，
    // 保证当前 +load 方法同时只有一次被调用
    if (loading) return;
    loading = YES;

    // 创建自动释放池
    void *pool = objc_autoreleasePoolPush();

    do {
        // 1. 不停调用类的 + load 方法
        while (loadable_classes_used > 0) {
            // 调用 loadable_classes 中的的类的 +load 函数，并且把 loadable_classes_used 置为 0
            call_class_loads();
        }

        // 2. 调用 分类中的 +load 函数， 只调用一次 call_category_loads
        // 因为上面的 call_class_loads 函数内部，已经把 loadable_classes_used 置为 0，所以除非有新的分类需要 +load，即 call_category_loads 返回 true，否则循环就结束了。 
        more_categories = call_category_loads();

        // 3. Run more +loads if there are classes OR more untried categories
    } while (loadable_classes_used > 0  ||  more_categories);
    // 如果 loadable_classes_used 大于 0，或者有更多分类需要调用 +load，则循环继续。（一般 loadable_classes_used 到这里基本就是 0 了）
    
    // 自动释放池进行 pop
    objc_autoreleasePoolPop(pool);

    // 标记处理完成了，可以进行下一个了
    loading = NO;
}
```

### 4.6 关于 +load 方法的几个QA

Q: +load的应用？

A: `load` 可以说我们在日常开发中可以接触到的调用时间**最靠前的方法**，在主函数运行之前，`load` 方法就会调用。

由于它的调用*不是惰性*(non-lazy)的，且其只会在程序调用期间调用一次，最最重要的是，如果在类与分类中都实现了 `load` 方法，它们都会被调用，不像其它的在分类中实现的方法会被覆盖，这就使 `load` 方法成为了[Method Swizzling](http://nshipster.com/method-swizzling/)的绝佳时机。

因为 load 调用时机过早，并且当多个 Class 没有关联（继承与派生），我们无法知道 Class 中 load 方法的优先调用关系，所以一般不会在 load 方法中引入其他的类，这是在开发当中需要注意的。

不过在这个时间点，所有的 framework 都已经加载到了运行时中，所以调用 framework 中的方法都是安全的。

Q: 重载自己 Class 的 +load 方法时需不需要调父类？

A: runtime 负责按继承顺序递归调用，所以我们不能调 super

Q: 在自己 Class 的 +load 方法时能不能替换系统 framework（比如 UIKit）中的某个类的方法实现

A: 可以，因为动态链接过程中，所有依赖库的类是先于自己的类加载的

Q: 重载 +load 时需要手动添加 @autoreleasepool 么？

A: 不需要，在 runtime 调用 +load 方法前后是加了 objc_autoreleasePoolPush() 和 objc_autoreleasePoolPop() 的。

Q: 想让一个类的 +load 方法被调用是否需要在某个地方 import 这个文件

A: 不需要，只要这个类的符号被编译到最后的可执行文件中，+load 方法就会被调用（Reveal SDK 就是利用这一点，只要引入到工程中就能工作）

## 五、类的加载过程总结

类存在懒加载机制，懒加载类先标记为 future class，正式加载 future class 数据需要调用`readClass(...)`方法，对 future class 进行重映射（remapping）；

截止至完成 class realizing，类的加载过程大致如下图所示。

- future class列是懒加载类（future class）的流程，经过了“添加懒加载类->加载懒加载类信息->懒加载类重映射->实现懒加载类”四步；
- normal class列是普通的非懒加载类的加载流程，只经过“加载类信息->实现类”两个步骤。

<img src="/images/compilelink/37.png" alt="36" style="zoom:88%;" />

类完成 class realizing 后，还需要执行类及分类中的`load()`方法，最后在程序运行过程中第一次调用类的方法时（实现逻辑在`IMP lookUpImpOrForward(...)`函数中）触发`isInitialized()`检查，若未初始化，则需要先执行类的`initialize()`方法。至此，类正式加载完成。

> 注意：最后的 class initializing 严格意义上应该不属于类的加载过程，可以将其归为独立的类初始化阶段。类的加载在`load()`方法执行后就算是完成了。

## 六、unmap_images()

```c++
/*
 * Process the given image which is about to be unmapped by dyld.
 */
void 
unmap_image(const char *path __unused, const struct mach_header *mh)
{
    recursive_mutex_locker_t lock(loadMethodLock);
    mutex_locker_t lock2(runtimeLock);
    unmap_image_nolock(mh);
}
```

### 6.1 unmap_image_nolock()

```c++
void 
unmap_image_nolock(const struct mach_header *mh)
{
    if (PrintImages) {
        _objc_inform("IMAGES: processing 1 newly-unmapped image...\n");
    }

    header_info *hi;
    
    // Find the runtime's header_info struct for the image
    for (hi = FirstHeader; hi != NULL; hi = hi->getNext()) {
        if (hi->mhdr() == (const headerType *)mh) {
            break;
        }
    }

    if (!hi) return;

    if (PrintImages) {
        _objc_inform("IMAGES: unloading image for %s%s%s\n", 
                     hi->fname(),
                     hi->mhdr()->filetype == MH_BUNDLE ? " (bundle)" : "",
                     hi->info()->isReplacement() ? " (replacement)" : "");
    }

    _unload_image(hi);

    // Remove header_info from header list
    removeHeader(hi);
    free(hi);
}
```

### 6.2 _unload_image()

```c++
/***********************************************************************
* _unload_image
* Only handles MH_BUNDLE for now.
* Locking: write-lock and loadMethodLock acquired by unmap_image
**********************************************************************/
void _unload_image(header_info *hi)
{
    size_t count, i;

    loadMethodLock.assertLocked();
    runtimeLock.assertLocked();

    // Unload unattached categories and categories waiting for +load.

    // Ignore __objc_catlist2. We don't support unloading Swift
    // and we never will.
    category_t * const *catlist = hi->catlist(&count);
    for (i = 0; i < count; i++) {
        category_t *cat = catlist[i];
        Class cls = remapClass(cat->cls);
        if (!cls) continue;  // category for ignored weak-linked class

        // fixme for MH_DYLIB cat's class may have been unloaded already

        // unattached list
        objc::unattachedCategories.eraseCategoryForClass(cat, cls);

        // +load queue
        remove_category_from_loadable_list(cat);
    }

    // Unload classes.

    // Gather classes from both __DATA,__objc_clslist 
    // and __DATA,__objc_nlclslist. arclite's hack puts a class in the latter
    // only, and we need to unload that class if we unload an arclite image.

    objc::DenseSet<Class> classes{};
    classref_t const *classlist;

    classlist = _getObjc2ClassList(hi, &count);
    for (i = 0; i < count; i++) {
        Class cls = remapClass(classlist[i]);
        if (cls) classes.insert(cls);
    }

    classlist = hi->nlclslist(&count);
    for (i = 0; i < count; i++) {
        Class cls = remapClass(classlist[i]);
        if (cls) classes.insert(cls);
    }

    // First detach classes from each other. Then free each class.
    // This avoid bugs where this loop unloads a subclass before its superclass

    for (Class cls: classes) {
        remove_class_from_loadable_list(cls);
        detach_class(cls->ISA(), YES);
        detach_class(cls, NO);
    }
    for (Class cls: classes) {
        free_class(cls->ISA());
        free_class(cls);
    }

    // XXX FIXME -- Clean up protocols:
    // <rdar://problem/9033191> Support unloading protocols at dylib/image unload time

    // fixme DebugUnload
}
```




## 七、参考链接

- [Runtime源代码解读2（类和对象）](https://juejin.cn/post/6844903965201530888#heading-0)

