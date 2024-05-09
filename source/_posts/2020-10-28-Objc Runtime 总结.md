---
title: Objc Runtime总结
date: 2020-10-28 10:26:09
urlname: runtime-data-structure.html
tags:
categories:
  - iOS
---

> 内容骨架来自戴铭老师文章[Objc Runtime 总结](https://ming1016.github.io/2015/04/01/objc-runtime/)，因为发布有些久远，一些内容已经过时，修正了一下，并填充了一些自己的知识总结。
>
> 更新：以下源码来自objc4-756.2，2019年下半年随着macOS 10.15发布了objc4-779.1，其后陆续对cache_t、class_rw_t等结构进行了一些调整。

# 一、Runtime概述

## 1.1 Runtime做了什么？

Objective-C跟C、C++等语言有着很大的不同，是一门动态性比较强的编程语言。允许很多操作推迟到程序运行时再进行，其可以在运行过程中修改之前编译好的行为，比如程序运行时创建，检查，修改类、对象和它们的方法。

> 维基：**动态编程语言**是高级编程语言的一个类别，是一类在运行时可以改变其结构的语言，或者说可以在运行时执行静态编程语言在编译期间执行的许多常见编程行为。例如：程序的扩展、添加新代码，已有的函数可以被删除或修改、扩展对象、定义或修改类型系统等。

而Objective-C的动态性是由Runtime来支撑和实现的。

> 很久之前孙源老师的一篇文章中说道：objc = C + objc编译器 + runtime

Runtime做了什么：

- 建立了支持objc语言的数据结构。使得C具有了面向对象能力
- 建立了消息机制

<img src="/images/runtime/04.jpg" alt="04" style="zoom:60%;" />

## 1.2 学习链接

- Runtime是C和汇编编写的，是开源的，[下载地址](https://opensource.apple.com/source/objc4/)；
- GNU也有一个开源的runtime版本，他们都努力的保持一致。
- 苹果官方的[Objective-C Runtime Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Introduction/Introduction.html#//apple_ref/doc/uid/TP40008048)。
- Runtime系统是由一系列的函数和数据结构组成的公共接口动态共享库，在/usr/include/objc目录下可以看到头文件，可以用其中一些函数通过C语言实现objectivec中一样的功能。可以在苹果官方文档[Objective-C Runtime Reference](https://developer.apple.com/documentation/objectivec/objective-c_runtime?language=objc)中查看 Runtime 库函数的详细解释。
  - 当我们导入了objc/Runtime.h和objc/message.h两个头文件之后，如果发现没有代码提示，函数里面的参数和描述也没有了。可以在 `Build Setting` 中设置 `Enable Strict Checking of objc_msgSend Calls` 为 NO。

写在前面：

- 后缀 `_t` 意味着 type/typedef(类型) ，是一种命名规范，类似于全局变量加前缀 `g_`。
- `_np`表示不可移植(np意指non portable, 不可移植)。

# 二、Object、Class与MetaClass

## 关系简图

<img src="/images/compilelink/36.png" alt="36" style="zoom:88%;" />

class_ro_t里面的baseMethodList、baseProtocols、ivars、baseProperties是一维数组，是只读的，包含了类的初始内容。

class_rw_t里面的methods、properties、protocols是二维数组，是可读可写的，包含了类的初始内容、分类的内容。

objc_class 1.0和2.0的差别示意图：

<img src="/images/runtime/08.png" alt="08" style="zoom:67%;" />

## 2.1 objc_object与id

```c++
/// 类的实例结构体
struct objc_object {
    isa_t isa;
    //方法略...
}

/// A pointer to an instance of a class. id是一个objc_object结构类型的指针，这个类型的对象能够转换成任何一种对象。
typedef struct objc_object *id;
```

### 对象是什么？

**看到 objc_object 的结构后，此处有个结论：任何结构体，只要以一个指向 Class 结构体的指针开始，都可以视为一个 objc_object (对象)。**

> - **32位中，只要一个数据结构的前4个字节，是个指针(Class isa)，就是个对象。**
>- **64位中，只要一个数据结构的前8个字节，是个isa_t类型的变量(isa_t isa)，就是个对象。**

**反之，Objc中的对象是一个指向ClassObject地址的变量，即 id obj = &ClassObject ， 而对象的实例变量 void \*ivar = &obj + offset(N)**

```objc
@interface Sark : NSObject
@property (nonatomic, copy) NSString *name;
- (void)speak;
@end
  
@implementation Sark
- (void)speak {
    NSLog(@"my name's %@", self.name);
}
@end
  
@implementation ViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    id cls = [Sark class];
    void *obj = &cls;
    [(__bridge id)obj speak];  
    // obj的前8个字节是指向Class Sark的数据，所以其能视为Sark类对象的。
    // 但是在-speak中，取obj的name，本质是取obj后偏移的第9-16字节的数据，此处会取出-viewDidLoad函数栈中的数据，错乱掉。
}
@end 
```

## 2.2 objc_class

```c++
/// Objc的类的本身也是一个Object，类的类型我们称为元类Meta Class，记录类方法、属性。
struct objc_class : objc_object {
    // 继承了isa_t isa;
    Class superclass;          // 指向父类的指针，用于组织类的继承链；
    cache_t cache;             // 缓存调用过的method。对象接到一个消息会根据isa指针查找消息对象，这时会在methodLists中遍历，如果cache了，常用的方法调用时就能够提高调用的效率。(以前缓存指针pointer和vtable)
    class_data_bits_t bits;    
       // class_rw_t * plus custom rr/alloc flags. 
       // 表示class_data_bits_t其实是class_rw_t* 加上自定义的rr/alloc标志，rr/alloc标志是指含有的retain/release/autorelease/retainCount/alloc等
  
       // class_data_bits_t结构体主要用于记录，保存类的数据的`class_rw_t`结构体的内存地址。通过`date()`方法访问`bits`的有效位域指向的内存空间，返回`class_rw_t`结构体；`setData(class_rw_t *newData)`用于设置`bits`的值；

    class_rw_t *data() { 
        return bits.data();
    }
    void setData(class_rw_t *newData) {
        bits.setData(newData);
    }
```

### 2.2.1 成员: isa_t isa

在arm64架构之前，isa就是一个普通的指针(Class _Nonnull isa)，存储着Class、Meta-Class对象的内存地址 

```c++
struct objc_class {
    Class isa OBJC_ISA_AVAILABILITY;
} OBJC2_UNAVAILABLE;
```

从arm64架构开始：

- 明确的将objc_class定义为一个Object，继承自struct objc_object。
- 对isa进行了优化，变成了一个共用体（union）结构，使用位域来存储了更多的信息。
```c++
struct objc_object {
    isa_t isa;   // isa(is a)指向它的类。当向object发送消息时，Runtime库会根据object的isa指针找到这个实例object所属于的类，然后在类的方法列表以及父类方法列表寻找对应的方法运行。
}

struct objc_class : objc_object {
    // 继承了isa_t isa;    // class的isa指针指向class的类(术语称为Meta Class)，因为Objc的类的本身也是一个Object，为了处理这个关系，runtime就创造了Meta Class，当给类发送[NSObject alloc]这样消息时，实际上是把这个消息发给了Class Object。
}

#define ISA_MASK        0x0000000ffffffff8ULL  取类指针值的掩码
#define ISA_MAGIC_MASK  0x000003f000000001ULL  取MAGIC值的掩码
union isa_t {
    isa_t() { }
    isa_t(uintptr_t value) : bits(value) { }
    Class cls;
    uintptr_t bits;
    struct {
        uintptr_t nonpointer        : 1;  // 代表是否开启isa指针优化。0 代表普通的指针，存储着Class、Meta-Class对象的内存地址； 1 代表优化过，使用位域存储更多的信息
        uintptr_t has_assoc         : 1;  // 是否设置或曾经过关联对象(associatedObject)，如果没有，释放时会更快
        uintptr_t has_cxx_dtor      : 1;  // 是否有C++ 或者 Objc的析构函数（.cxx_destruct），如果没有，释放时会更快
        uintptr_t shiftcls          : 33; // 类指针。存储着Class、Meta-Class对象的内存地址信息。源码中isa.shiftcls = (uintptr_t)cls >> 3; 将当前地址右移三位的主要原因是用于将 Class 指针中无用的后三位清除减小内存的消耗，因为类的指针要按照字节（8 bits）对齐内存，其指针后三位都是没有意义的 0。
        uintptr_t magic             : 6;  // 用于在调试时分辨对象是否未完成初始化
        uintptr_t weakly_referenced : 1;  // 对象被指向或者曾经指向一个 ARC 的弱变量。如果没有，释放时会更快
        uintptr_t deallocating      : 1;  // 对象是否正在释放
        uintptr_t has_sidetable_rc  : 1;  // 引用计数器是否过大无法存储在isa(extra_rc字段)中。如果为1，那么引用计数会存储在一个叫SideTable的类的属性中
        uintptr_t extra_rc          : 19  // 里面存储的值是引用计数器减1（比如对象引用计数器是1，这里就是0）
    };
}                                     
```

#### 关于Tagged Pointer

在2013年9月，苹果推出了[iPhone5s](https://link.jianshu.com?t=http://en.wikipedia.org/wiki/IPhone_5S)，与此同时，iPhone5s配备了首个采用64位架构的[A7双核处理器](https://link.jianshu.com?t=http://en.wikipedia.org/wiki/Apple_A7)，为了节省内存和提高执行效率，苹果提出了Tagged Pointer的概念。对于64位程序，引入Tagged Pointer后，相关逻辑能减少一半的内存占用，以及3倍的访问速度提升，100倍的创建、销毁速度提升。

在WWDC2013的《Session 404 Advanced in Objective-C》视频中，苹果介绍了 Tagged Pointer。 Tagged Pointer用于优化NSNumber、NSDate、NSString等小对象的存储，其存在主要是为了节省内存。我们知道，对象的指针大小一般是与机器字长有关，在32位系统中，一个指针的大小是32位（4字节），而在64位系统中，一个指针的大小将是64位（8字节）。

假设我们要存储一个NSNumber对象，其值是一个整数。正常情况下，如果这个整数只是一个NSInteger的普通变量，那么它所占用的内存是与CPU的位数有关，在32位CPU下占4个字节，在64位CPU下是占8个字节的。而指针类型的大小通常也是与CPU位数相关，一个指针所占用的内存在32位CPU下为4个字节，在64位CPU下也是8个字节。如果没有Tagged Pointer对象，从32位机器迁移到64位机器中后，虽然逻辑没有任何变化，但这种NSNumber、NSDate一类的对象所占用的内存会翻倍。

苹果提出了Tagged Pointer对象。由于NSNumber、NSDate一类的变量本身的值需要占用的内存大小常常不需要8个字节，拿整数来说，4个字节所能表示的有符号整数就可以达到20多亿（注：2^31=2147483648，另外1位作为符号位)，对于绝大多数情况都是可以处理的。如下图所示：

<img src="/images/runtime/05.png" alt="05" style="zoom:75%;" />

### 2.2.2 成员: cache_t cache

> cache: 用于缓存调用过的method

Cache的作用主要是为了优化方法调用的性能。

假如，当对象receiver调用方法message时：

1. 首先根据对象receiver的isa指针查找到它对应的类，然后在类的methodLists中搜索方法；
2. 如果没有找到，就使用super_class指针到父类中的methodLists查找，一旦找到就调用方法。如果没有找到，有可能消息转发，也可能忽略它。

这样查找方式效率就太低了，因为往往一个类大概只有20%的方法经常被调用，占总调用次数的80%。所以使用Cache来缓存经常调用的方法，当调用方法时，优先在Cache查找，如果没有找到，再到methodLists查找。

```c++
struct cache_t {
    struct bucket_t *_buckets;  // 是一个散列表，用来存储Method的链表
    mask_t _mask;               // 分配用来缓存bucket的总数。散列表的长度 - 1
    mask_t _occupied;           // 目前实际占用的缓存bucket的个数。因为缓存是以散列表的形式存在的，所以会有空槽，而occupied表示当前被占用的数目
}

typedef unsigned int uint32_t;
typedef uint32_t mask_t;  // x86_64 & arm64 asm are less efficient with 16-bits

typedef unsigned long  uintptr_t;
typedef uintptr_t cache_key_t;

struct bucket_t {
private:
  uintptr_t _imp;  // 函数指针，指向了一个方法的具体实现
  SEL _sel;        // SEL作为key
}

// 散列函数
static inline mask_t cache_hash(SEL sel, mask_t mask) 
{
    return (mask_t)(uintptr_t)sel & mask;
}
```

#### 要点：

- **不管是在本类、父类、基类中找到的，只要不在本类的cache中，就填充缓存。**详见4.3节
- 关于缓存的扩容以及限制：
  - 初始大小为4；
  - 当缓存使用达到3/4后，进行缓存扩容，扩容系数为2；
  - 扩容时，会清空缓存，否则hash值就不对了；
  - 旧版本中，类的方法缓存大小是有没有限制的，在新的runtime中增加了限制；
  ```c++
  /* Initial cache bucket count. INIT_CACHE_SIZE must be a power of two. */
  enum {
      INIT_CACHE_SIZE_LOG2 = 2,
      INIT_CACHE_SIZE      = (1 << INIT_CACHE_SIZE_LOG2),
      MAX_CACHE_SIZE_LOG2  = 16,
      MAX_CACHE_SIZE       = (1 << MAX_CACHE_SIZE_LOG2),
  };
  
  void cache_t::insert(Class cls, SEL sel, IMP imp, id receiver){
      //...
      capacity = capacity ? capacity * 2 : INIT_CACHE_SIZE;
      if (capacity > MAX_CACHE_SIZE) {
          capacity = MAX_CACHE_SIZE;
      }
      reallocate(oldCapacity, capacity, true);   
      //...
  }
  ```
- 为什么类的方法列表不直接做成散列表呢，做成list，还要单独缓存，多费事？这个问题么，我觉得有以下三个原因：
  - 散列表是没有顺序的，Objective-C的方法列表是一个list，是有顺序的；Objective-C在查找方法的时候会顺着list依次寻找，并且category的方法在原始方法list的前面，需要先被找到，如果直接用hash存方法，方法的顺序就没法保证。
  - list的方法还保存了除了selector和imp之外其他很多属性
  - 散列表是有空槽的，会浪费空间

### 2.2.3 成员: class_data_bits_t bits

#### 1. 数据结构

> `bits`：`class_data_bits_t`结构体类型，该结构体主要用于记录，保存类的数据的`class_rw_t`结构体的内存地址。

```c++
#if !__LP64__
#define FAST_DATA_MASK        0xfffffffcUL
#elif 1
#define FAST_DATA_MASK        0x00007ffffffffff8UL
#endif

struct class_data_bits_t {
    uintptr_t bits;  // 仅有一个成员 bits 指针。

private:
    bool getBit(uintptr_t bit) {
        return bits & bit;
    }
    //...
public:
    // 获取类的数据。获取 bits 成员的 4~47 位域(FAST_DATA_MASK)中保存的 class_rw_t 结构体地址。
    class_rw_t* data() {
        return (class_rw_t *)(bits & FAST_DATA_MASK);
    }

    // 设置类的数据
    void setData(class_rw_t *newData)
    {
        // 仅在类注册、构建阶段才允许调用setData
        assert(!data()  ||  (newData->flags & (RW_REALIZING | RW_FUTURE)));
        uintptr_t newBits = (bits & ~FAST_DATA_MASK) | (uintptr_t)newData;
        atomic_thread_fence(memory_order_release);
        bits = newBits;
    }
};
```

#### 2. class_rw_t与class_ro_t简介

`class_rw_t`、`class_ro_t`结构体名中，`rw`是 read write 的缩写，`ro`是 read only 的缩写，可见`class_ro_t`的保存类的只读信息，这些信息在类完成注册后不可改变。

即分类等运行期添加的数据保存在`class_rw_t`结构体中，编译时期就能确定的部分保存在`ro`指针指向的`class_ro_t`结构体中。

以类的成员变量列表为例（成员变量列表保存在`class_ro_t`结构体中）。若应用类注册到内存后，使用类构建了若干实例，此时若能够添加成员变量，那必然需要对内存中的这些类重新分配内存，这个操作的花销是相当大的。若考虑再极端一些，为根类`NSObject`添加成员变量，则内存中基本所有 Objective-C 对象都需要重新分配内存，如此庞大的计算量在运行时是不可接受的。

#### 3. bits在编译、运行期间值的改变

注意：**在编译期，类的结构中的 class_data_bits_t的 class_rw_t** ***data() 取出的是一个指向 class_ro_t 的指针。**

<img src="/images/runtime/06.png" alt="06" style="zoom:80%;" />

在运行时调用 realizeClass方法，会做以下3件事情：

1. 从 class_data_bits_t调用 data方法，将结果从 class_rw_t强制转换为 class_ro_t指针；
2. 初始化一个 class_rw_t结构体；
3. 设置结构体 ro的值以及 flag；
4. 最后设置正确的 `data`

```c++
auto ro = (const class_ro_t *)cls->data();
auto isMeta = ro->flags & RO_META;
rw = objc::zalloc<class_rw_t>();
rw->set_ro(ro);
rw->flags = RW_REALIZED|RW_REALIZING|isMeta;
cls->setData(rw);
```

但是，在这段代码运行之后 `class_rw_t` 中的方法，属性以及协议列表均为空。这时需要 `realizeClass` 调用 `methodizeClass` 方法来**将类自己实现的方法（包括分类）、属性和遵循的协议加载到 `methods`、 `properties` 和 `protocols` 列表中**。

<img src="/images/runtime/07.png" alt="06" style="zoom:80%;" />

更加详细的分析，请看[@Draveness](https://link.jianshu.com?t=https://github.com/Draveness) 的这篇文章[深入解析 ObjC 中方法的结构](https://draveness.me/method-struct/)。

### 2.2.4 方法: 类加载过程中，状态读写

```c++
    // objc_class结构体中与类的加载过程相关的方法：
    // 查询是否正在初始化（initializing）
    bool isInitializing() {
        return getMeta()->data()->flags & RW_INITIALIZING;
    }
    
    // 标记为正在初始化（initializing）
    void setInitializing() {
        assert(!isMetaClass());
        ISA()->setInfo(RW_INITIALIZING);
    }
    
    // 是否已完成初始化（initializing）
    bool isInitialized() {
        return getMeta()->data()->flags & RW_INITIALIZED;
    }
    
    void setInitialized(){
        Class metacls;
        Class cls;
    
        assert(!isMetaClass());
    
        cls = (Class)this;
        metacls = cls->ISA();
    
        // 关于alloc/dealloc/Retain/Release等特殊方法的判断及处理
        // ...
    
        metacls->changeInfo(RW_INITIALIZED, RW_INITIALIZING);
    }
    
    bool isLoadable() {
        assert(isRealized());
        return true;  // any class registered for +load is definitely loadable
    }
    
    // 获取load方法的IMP
    IMP objc_class::getLoadMethod()
    {
        runtimeLock.assertLocked();
    
        const method_list_t *mlist;
    
        assert(isRealized());
        assert(ISA()->isRealized());
        assert(!isMetaClass());
        assert(ISA()->isMetaClass());
    
        // 在类的基础方法列表中查询load方法的IMP
        mlist = ISA()->data()->ro->baseMethods();
        if (mlist) {
            for (const auto& meth : *mlist) {
                const char *name = sel_cname(meth.name);
                if (0 == strcmp(name, "load")) {
                    return meth.imp;
                }
            }
        }
        return nil;
    }
    
    // runtime是否已认识/实现类
    bool isRealized() {
        return data()->flags & RW_REALIZED;
    }
    
    // 是否future class
    bool isFuture() { 
        return data()->flags & RW_FUTURE;
    }
```

### 2.2.5 方法: 类状态获取

`objc_class`结构体中类的基本状态查询的函数代码如下。注意`Class getMeta()`获取元类时：对于元类，`getMeta()`返回的结果与`ISA()`返回的结果不相同，对于非元类，两者则是相同的。

```c++
    bool isARC() {
        return data()->ro->flags & RO_IS_ARC;
    }

    bool isMetaClass() {
        assert(this);
        assert(isRealized());
        return data()->ro->flags & RO_META;
    }

    bool isMetaClassMaybeUnrealized() {
        return bits.safe_ro()->flags & RO_META;
    }

    Class getMeta() {
        if (isMetaClass()) return (Class)this;
        else return this->ISA();
    }

    bool isRootClass() {
        return superclass == nil;
    }
    bool isRootMetaclass() {
        return ISA() == (Class)this;
    }

    const char *mangledName() { 
        assert(this);

        if (isRealized()  ||  isFuture()) {
            return data()->ro->name;
        } else {
            return ((const class_ro_t *)data())->name;
        }
    }
    
    const char *demangledName();
    const char *nameForLogging();
```

### 2.2.6 方法: 内存分配

根据类的信息构建对象时，需要根据类的继承链上的所有成员变量的内存布局为成员变量数据分配内存空间，分配内存空间的大小固定的，并按 WORD 对齐，调用`size_t class_getInstanceSize(Class cls)`实际是调用了`objc_class`结构体的`uint32_t alignedInstanceSize()`函数。

成员变量在实例内存空间中偏移量同样也是固定的，同样也是按 WORD 对齐。实例的第一个成员变量内存空间的在实例空间中的偏移量，实际是通过调用`objc_class`结构体的`uint32_t alignedInstanceStart()`函数获取。

`objc_class`结构体中涉及内存分配的函数代码如下：

```c++
    // 类的实例的成员变量起始地址可能不按WORD对齐
    uint32_t unalignedInstanceStart() {
        assert(isRealized());
        return data()->ro->instanceStart;
    }

    // 配置类的实例的成员变量起始地址按WORD对齐
    uint32_t alignedInstanceStart() {
        return word_align(unalignedInstanceStart());
    }

    // 类的实例大小可能因为ivar的alignment值而不按WORD对齐
    uint32_t unalignedInstanceSize() {
        assert(isRealized());
        return data()->ro->instanceSize;
    }

    // 配置类的实例大小按WORD对齐
    uint32_t alignedInstanceSize() {
        return word_align(unalignedInstanceSize());
    }

    // 获取类的实例大小
    size_t instanceSize(size_t extraBytes) {
        size_t size = alignedInstanceSize() + extraBytes;
        // CF requires all objects be at least 16 bytes. （TODO：不懂为啥）
        if (size < 16) size = 16;
        return size;
    }

    // 配置类的实例大小
    void setInstanceSize(uint32_t newSize) {
        assert(isRealized());
        if (newSize != data()->ro->instanceSize) {
            assert(data()->flags & RW_COPIED_RO);
            *const_cast<uint32_t *>(&data()->ro->instanceSize) = newSize;
        }
        bits.setFastInstanceSize(newSize);
    }
};
```

## 2.3 class_rw_t

类的主要数据保存在`bits`中，`bits`以位图保存`class_rw_t`结构体，用于记录类的关键数据，如成员变量列表、方法列表、属性列表、协议列表等等，`class_rw_t`仅包含三个基本的位操作方法。

```c++
#if __ARM_ARCH_7K__ >= 2  ||  (__arm64__ && !__LP64__)
#   define SUPPORT_INDEXED_ISA 1
#else
#   define SUPPORT_INDEXED_ISA 0
#endif

struct class_rw_t {
    uint32_t flags;       // 标记类的状态;
    uint32_t version;     // 标记类的类型，0表示类为非元类，7表示类为元类；

    const class_ro_t *ro; // 保存类的只读数据，注册类后ro中的数据标记为只读，成员变量列表保存在ro中；
    
    method_array_t methods;      // 方法列表，其类型method_array_t  为二维数组容器；
    property_array_t properties; // 属性列表，其类型property_array_t为二维数组容器；
    protocol_array_t protocols;  // 协议列表，其类型protocol_array_t为二维数组容器；
    
    Class firstSubclass;    // 类的首个子类，与nextSiblingClass记录所有类的继承链组织成的继承树；
    Class nextSiblingClass; // 类的下一个兄弟类；
    
    char *demangledName;    // 类名，来自Swift的类会包含一些特别前缀，demangledName是处理后的类名；

#if SUPPORT_INDEXED_ISA
    uint32_t index;      // 标记类的对象的isa是否为index类型；
#endif

    //设置set指定的位
    void setFlags(uint32_t set) 
    {
        OSAtomicOr32Barrier(set, &flags);
    }
    
    // 清空clear指定的位
    void clearFlags(uint32_t clear) 
    {
        OSAtomicXor32Barrier(clear, &flags);
    }
    
    // 设置set指定的位，清空clear指定的位
    void changeFlags(uint32_t set, uint32_t clear) 
    {
        assert((set & clear) == 0);
    
        uint32_t oldf, newf;
        do {
            oldf = flags;
            newf = (oldf | set) & ~clear;
        } while (!OSAtomicCompareAndSwap32Barrier(oldf, newf, (volatile int32_t *)&flags));
    }
};
```

## 2.4 class_ro_t

```c++
struct class_ro_t {
    uint32_t flags;         // 标记类的状态。需要注意class_ro_t的flags的值和前面介绍的class_rw_t的flags的值是完全不同的；
    uint32_t instanceStart; // 类的成员变量，在实例的内存空间中的起始偏移量；
    uint32_t instanceSize;  // 类的实例占用的内存空间大小；
#ifdef __LP64__
    uint32_t reserved;
#endif

    const uint8_t * ivarLayout;     // strong成员变量内存布局。
    
    const char * name;              // 类名；
    method_list_t * baseMethodList; // 基础方法列表，在类定义时指定的方法列表；
    protocol_list_t * baseProtocols;// 协议列表；
    const ivar_list_t * ivars;      // 成员变量列表；
    
    const uint8_t * weakIvarLayout; // weak成员变量布局；
    property_list_t *baseProperties;// 基础属性列表，在类定义时指定的属性列表；
    
    ...
    
    method_list_t *baseMethods() const {
        return baseMethodList;
    }
    
    class_ro_t *duplicate() const {
        if (flags & RO_HAS_SWIFT_INITIALIZER) {
            size_t size = sizeof(*this) + sizeof(_swiftMetadataInitializer_NEVER_USE[0]);
            class_ro_t *ro = (class_ro_t *)memdup(this, size);
            ro->_swiftMetadataInitializer_NEVER_USE[0] = this->_swiftMetadataInitializer_NEVER_USE[0];
            return ro;
        } else {
            size_t size = sizeof(*this);
            class_ro_t *ro = (class_ro_t *)memdup(this, size);
            return ro;
        }
    }
};
```

### 2.4.1 ivarLayout与weakIvarLayout

#### 1. 值的存储格式

ivarLayout 和 weakIvarLayout 这两个编码值，结合起来，就可以确定**自上而下**，哪些 ivar 是strong、weak，确定了这两种之后，剩余的就都是基本类型和 __unsafe_unretained 的对象类型。

这两者都是 `const uint8_t *` 类型，但读取值的时候，需要注意，不是以char(1字节)为单位来读取的，而是：

- **4bit为一位，1字节为一对**，即**从两者首地址开始，1字节分为一对**来读取
- 以两位 **00** 为结束符，就像 cstring 的 **\0** 一样

ivarLayout 的每1位(4bit)依次表示：成员变量自上而下，多少个 **非 strong** 成员变量、多少个 **strong** 成员变量...(**循环**)...直到最后一个strong出现的位置(后面的就不记录了)。

weakIvarLayout 的每1位(4bit)依次表示：成员变量自上而下，多少个 **非 weak** 成员变量、多少个 **weak** 成员变量...(**循环**)...直到最后一个weak出现的位置(后面的就不记录了)。

#### 2. 操作函数

这两个值可以通过 runtime 提供的几个 API 来访问：

```c++
typedef unsigned char uint8_t;

const uint8_t *class_getIvarLayout(Class cls)
const uint8_t *class_getWeakIvarLayout(Class cls)
void class_setIvarLayout(Class cls, const uint8_t *layout)
void class_setWeakIvarLayout(Class cls, const uint8_t *layout)
```

#### 3. 示例

```objc
@interface Foo : NSObject{
    __weak id ivar0;
    __strong id ivar1;
    __unsafe_unretained id ivar2;
    __weak id ivar3;
    __strong id ivar4;
    __weak id ivar5;
    __weak id ivar6;
    __strong id ivar7;
    __strong id ivar8;
}
@property (nonatomic, strong) id ivv;
@property (nonatomic, weak) id ivv1;
@end
  
const uint8_t * strongLayout = class_getIvarLayout(Foo.class);
const uint8_t * weakLayout = class_getWeakIvarLayout(Foo.class);

(lldb) p strongLayout
(const uint8_t *) $0 = 0x000000010d6c1246 "\U00000011!#"
(lldb) p weakLayout
(const uint8_t *) $1 = 0x000000010d6c124a "\U00000001!\U000000121"
(lldb) x/4xb $0
0x10d6c1246: 0x11 0x21 0x23 0x00
  /*
   解释：
   0x11: 1个非strong、1个strong
   0x21: 2个非strong、1个strong
   0x23: 2个非strong、3个strong （后面还有个weak就不记录了）
   0x00: 结束符
   */
(lldb) x/5xb $1
0x10d6c124a: 0x01 0x21 0x12 0x31 0x00
  /*
   解释：
   0x01: 0个非weak、1个weak
   0x21: 2个非weak、1个weak
   0x12: 1个非weak、2个weak
   0x31: 3个非weak、1个weak
   0x00: 结束符
   */
```

#### 4. 使用场景

[原文链接：Objective-C Class Ivar Layout 探索](http://blog.sunnyxx.com/2015/09/13/class-ivar-layout/)

当我们定义一个类的实例变量的时候，可以指定其修饰符：

```objc
@interface Sark : NSObject {
    __strong id _gayFriend; // 无修饰符的对象默认会加 __strong
    __weak id _girlFriend;
    __unsafe_unretained id _company;
}
@end
```

这使得 ivar (instance variable) 可以像属性一样在 ARC 下进行正确的引用计数管理。

那么问题来了，假如这个类是动态生成的：

```objc
Class class = objc_allocateClassPair(NSObject.class, "Sark", 0);
class_addIvar(class, "_gayFriend", sizeof(id), log2(sizeof(id)), @encode(id));
class_addIvar(class, "_girlFriend", sizeof(id), log2(sizeof(id)), @encode(id));
class_addIvar(class, "_company", sizeof(id), log2(sizeof(id)), @encode(id));
objc_registerClassPair(class);
```

该如何像上面一样来添加 ivar 的属性修饰符呢？假如依次设置strong、weak、strong修饰符

第一步：

```objc
// 在objc_registerClassPair(class);前加上这么两句
class_setIvarLayout(class, (const uint8_t *)"\x01\x11\x00"); // <--- new
class_setWeakIvarLayout(class, (const uint8_t *)"\x11\x10\x00"); // <--- new
```

第二步：

此时，strong 和 weak 的内存管理并没有生效，继续研究发现， class 的 flags 中有一个标记位记录这个类是否 ARC，正常编译的类，且标识了 **-fobjc-arc** flag 时，这个标记位为 1，而动态创建的类并没有设置它。所以只能继续黑魔法，运行时把这个标记位设置上，探索过程不赘述了，实现如下：

```c++
static void fixup_class_arc(Class class) {
    struct {
        Class isa;
        Class superclass;
        struct {
            void *_buckets;
#if __LP64__
            uint32_t _mask;
            uint32_t _occupied;
#else
            uint16_t _mask;
            uint16_t _occupied;
#endif
        } cache;
        uintptr_t bits;
    } *objcClass = (__bridge typeof(objcClass))class;
#if !__LP64__
#define FAST_DATA_MASK 0xfffffffcUL
#else
#define FAST_DATA_MASK 0x00007ffffffffff8UL
#endif
    struct {
        uint32_t flags;
        uint32_t version;
        struct {
            uint32_t flags;
        } *ro;
    } *objcRWClass = (typeof(objcRWClass))(objcClass->bits & FAST_DATA_MASK);
#define RO_IS_ARR 1<<7    
    objcRWClass->ro->flags |= RO_IS_ARR;
}
```

把这个 fixup 放在 `objc_registerClassPair(class);` 之后，这个动态的类终于可以像静态编译的类一样操作 ivar 了。

完整的示例：

```objc
Class class = objc_allocateClassPair(NSObject.class, "Sark", 0);
class_addIvar(class, "_gayFriend", sizeof(id), log2(sizeof(id)), @encode(id));
class_addIvar(class, "_girlFriend", sizeof(id), log2(sizeof(id)), @encode(id));
class_addIvar(class, "_company", sizeof(id), log2(sizeof(id)), @encode(id));
class_setIvarLayout(class, (const uint8_t *)"\x01\x11\x00"); // <--- new
class_setWeakIvarLayout(class, (const uint8_t *)"\x11\x10\x00"); // <--- new
objc_registerClassPair(class);
fixup_class_arc(class);

id sark = [class new];
Ivar strongIvar = class_getInstanceVariable(class, "_gayFriend");
Ivar weakIvar = class_getInstanceVariable(class, "_girlFriend");
Ivar strongIvar2 = class_getInstanceVariable(class, "_company");

{
    id boy = [NSObject new];
    id girl = [NSObject new];
    id boy2 = [NSObject new];
    object_setIvar(sark, strongIvar, boy);
    object_setIvar(sark, weakIvar, girl);
    object_setIvar(sark, strongIvar2, boy2);
} // ARC 在这里会对大括号内的 girl、boy、boy2 做一次release

NSLog(@"%@, %@, %@", object_getIvar(sark, strongIvar),  //<NSObject: 0x600000934660>
                     object_getIvar(sark, weakIvar),    //nil
                     object_getIvar(sark, strongIvar2));//<NSObject: 0x6000009346a0>
```

### 2.4.2 几点总结

- property在编译期会生成 _propertyName 的ivar，和相应的get/set方法。
- ivars在编译期确定，但不完全确定，offset属性在运行时会修改。
- 对象的大小是由ivars决定的，当有继承体系时，父类的ivars永远放在子类之前。
- class_ro_t 的 instanceStart 和 instanceSize 会在运行时调整。
- class_ro_t 的 ivarLayout 和 weakIvarLayout 存放的是强ivar和弱ivar的存储规则。

## 2.5 元类(Meta Class)

### 2.5.1 为什么存在元类？

**在调用类方法的时候，为了和对象查找方法的机制一致，遂引入了元类(meta-class)的概念。**

- 对象的实例方法调用时，通过对象的 isa 在类中获取方法的实现。
- 类对象的类方法调用时，通过类的 isa 在元类中获取方法的实现。

meta-class之所以重要，是因为它存储着一个类的所有类方法。每个类都会有自己独一无二的meta-class，因为每个类的类方法基本不可能完全相同。

> 以下元类的相关内容，都来自 [What is a meta-class in Objective-C?](https://link.jianshu.com?t=http://www.cocoawithlove.com/2010/01/what-is-meta-class-in-objective-c.html) 这篇文章。

### 2.5.2 元类的isa — 类

元类，和类的结构是一样的 objc_class，所以也是一个对象。这表示你能够对元类调用方法。自然的，这表示它必须也有一个类指针。

- 类创建对象，调用的是实例方法
- 元类创建类对象，调用的是类方法。

所有元类使用基类的元类（即继承链顶端的类的元类）作为它们的类，而所有类的基类都是 NSObject（大多数类是这样的）。所以：

- 大多数元类使用 NSObject 的元类作为它的类。
- 基类的元类就是它自己的类，即NSObject的元类的isa指针指向的是它自己（它是一个它自己的实例）。

### 2.5.3 元类的superclass — 父类

同样的，类使用 super_class 指针指向他们的 superclass，元类也有 super_class 指针来指向 superclass。

这里又有一个奇怪的地方，基类的元类设置的 superclass 是基类自己 (**NSObject->isa->superclass = NSObject**)。

这种继承结构导致的结果是所有结构中的实例、类以及元类都继承自结构中的基类。

### 2.5.4 总结

所有这些用文字描述起来可能比较容易让人困惑。[Greg Parker的文章](https://link.jianshu.com/?t=http://www.sealiesoftware.com/blog/archive/2009/04/14/objc_explain_Classes_and_metaclasses.html)中有一张附图描述了实例、类和元类以及他们的super class是如何完美的共存的。

<img src="/images/runtime/01.png" alt="01" style="zoom:85%;" />

可以看到，所有的meta class 与 Root class 的 isa 都指向 Root class 的meta class，这样能够形成一个闭环。

实现了：

- 所有 NSObject 的实例方法，都能够被 **任何实例、类、元类** 来使用；
- 所有 NSObject 的类方法，都能够被 **任何类、元类** 来使用。

即实现了**Objc中的任意 objc_object 对象，都继承自NSObject。NSObject为所有的对象定义了一些相同的特性**。

## 2.6 类与对象操作函数

runtime有很多的函数可以操作类和对象。通常，操作类的是class为前缀，操作对象的是objc或object_为前缀(因为class也是一种Object，所以有的objc或object为前缀的函数也可以操作类对象)。

### 2.6.1 类型获取和判断函数

#### 1. 类型获取

```c++
/**
  传入字符串类名，返回对应的类对象
  Return the id of the named class.  If the class does not exist, call _objc_classLoader and then objc_classHandler, either of which may create a new class.
 */
Class objc_getClass(const char *aClassName)
{
    if (!aClassName) return Nil;

    // NO unconnected, YES class handler
    return look_up_class(aClassName, NO, YES);
}

/**
 传入的obj可能是instance对象、class对象、meta-class对象
 返回:
  a) 如果是instance对象，返回class对象
  b) 如果是class对象，返回meta-class对象
  c) 如果是meta-class对象，返回NSObject（基类）的meta-class对象
 */
Class object_getClass(id obj)
{
    if (obj) return obj->getIsa();
    else return Nil;
}

/// 返回的就是类对象
- (Class)class {
    return object_getClass(self);
}
+ (Class)class {
    return self;
}
```

#### 2. 类型判断

```c++
/**
 判断调用者的类是不是cls类
    id person = [[MJPerson alloc] init];
    NSLog(@"%d", [person isMemberOfClass:[MJPerson class]]);  // 1
    NSLog(@"%d", [person isMemberOfClass:[NSObject class]]);  // 0
 */
- (BOOL)isMemberOfClass:(Class)cls {
    return [self class] == cls;
}
/**
 判断调用者(类对象)的类(即元类)是不是cls。(cls需要传入元类，才有可能返回YES)
    NSLog(@"%d", [MJPerson isMemberOfClass:object_getClass([MJPerson class])]); // 1
    NSLog(@"%d", [MJPerson isMemberOfClass:[NSObject class]]); // 0 类对象的类怎么可能还是class
 */
+ (BOOL)isMemberOfClass:(Class)cls {
    return object_getClass((id)self) == cls;
}

/**
 判断调用者的类是不是cls类、或者cls子类
    NSLog(@"%d", [person isKindOfClass:[MJPerson class]]);  // 1
    NSLog(@"%d", [person isKindOfClass:[NSObject class]]);  // 1
 */
- (BOOL)isKindOfClass:(Class)cls {
    for (Class tcls = [self class]; tcls; tcls = tcls.superclass) {
        if (tcls == cls) return YES;
    }
    return NO;
}

/**
 判断调用者(类对象)的类(即元类)是不是cls、或者cls子类。(cls需要传入元类，才有可能返回YES)
    NSLog(@"%d", [MJPerson isKindOfClass:object_getClass([NSObject class])]); // 1
    NSLog(@"%d", [MJPerson isKindOfClass:[NSObject class]]); // 1 特殊的NSObject，NSObject是所有元类的最顶部父类
 */
+ (BOOL)isKindOfClass:(Class)cls {
    for (Class tcls = object_getClass((id)self); tcls; tcls = tcls.superclass) {
        if (tcls == cls) return YES;
    }
    return NO;
}
```

#### 3. 判断是否是元类

```c++
// 判断给定的Class是否是一个meta class
BOOL class_isMetaClass(Class cls)
{
    if (!cls) return NO;
    return cls->isMetaClass();
}
```

### 2.6.2 类相关操作函数

#### 1. 获取name

```c++
// 获取类的类名
const char *class_getName(Class cls)
{
    if (!cls) return "nil";
    // fixme lldb calls class_getName() on unrealized classes (rdar://27258517)
    // ASSERT(cls->isRealized()  ||  cls->isFuture());
    return cls->demangledName(/* needs lock */true);
}
```

> **名字修饰**（name decoration），也称为**名字重整**、**名字改编**（name mangling），是现代计算机程序设计语言的编译器用于解决由于程序实体的名字必须唯一而导致的问题的一种技术。
>
> demangledName: 去除修饰的名称。

#### 2. 获取super_class

```c++
// 获取类的父类
Class class_getSuperclass(Class cls)
{
    if (!cls) return nil;
    return cls->superclass;
}
```

#### 3. 获取instance_size

```c++
// 获取实例大小
size_t class_getInstanceSize(Class cls)
{
    if (!cls) return 0;
    return cls->alignedInstanceSize();
}
```

#### 4. 成员变量(ivars)操作

```c++
struct ivar_t {
    int32_t *offset;
    const char *name;
    const char *type;
    // alignment is sometimes -1; use alignment() instead
    uint32_t alignment_raw;
    uint32_t size;
};

typedef struct ivar_t *Ivar;

// 获取类中指定名称实例成员变量的信息
Ivar class_getInstanceVariable(Class cls, const char *name)
{
    if (!cls  ||  !name) return nil;
    return _class_getVariable(cls, name);
}

// 获取类成员变量的信息
Ivar class_getClassVariable(Class cls, const char *name)
{
    if (!cls) return nil;
    return class_getInstanceVariable(cls->ISA(), name);
}

// 添加成员变量(这个只能够向在runtime时创建的类添加成员变量)
BOOL class_addIvar(Class cls, 
                   const char *name, 
                   size_t size, 
                   uint8_t alignment, 
                   const char *type)

// 获取整个成员变量列表(必须使用free()来释放这个数组)
Ivar * class_copyIvarList(Class cls, unsigned int *outCount)
```

#### 5. 方法操作

```c++
typedef struct method_t *Method;

// 获取实例方法。注意：如果这个类中没有实现selector这个方法，会沿着继承链向上找到为止，即可能会返回它某父类中的Method对象
Method class_getInstanceMethod (Class cls, SEL name);

// 获取类方法
Method class_getClassMethod (Class cls, SEL name);

// 获取所有方法的数组
Method * class_copyMethodList (Class cls, unsigned int *outCount);

// 添加方法. 和成员变量不同的是可以为类动态添加方法。
/*
  class_addMethod可以添加父类中方法实现的override，但不会替换该类中的现有实现。
  如果已有同名的方法实现（包含分类中的方法）会返回NO。要更改现有的实现，请使用method_setImplementation。
 */
BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types)

// 替代方法的实现。返回cls标识的类中，name标识的方法的以前实现。
/*
 * 如果通过名称标识的方法还不存在(本类、分类中都没实现)，就会像调用class_addMethod一样添加它。使用由types指定的类型编码。
 * 返回：NULL
 * 如果通过名称标识的方法确实存在(本类或分类中实现了)，那么它的IMP将被替换，就像调用了method_setImplementation一样。类型指定的类型编码将被忽略。
 * 返回：SEL name之前的实现IMP
 */
IMP class_replaceMethod(Class cls, SEL name, IMP imp, const char *types)

// 返回方法的具体实现
IMP class_getMethodImplementation(Class cls, SEL name);
IMP class_getMethodImplementation_stret(Class cls, SEL name);

// 类实例是否响应指定的selector
BOOL class_respondsToSelector(Class cls, SEL sel);
```

#### 6. 协议操作

```c++
// 添加协议
BOOL class_addProtocol(Class cls, Protocol *protocol_gen);

// 返回类是否实现指定的协议
BOOL class_conformsToProtocol(Class cls, Protocol *proto_gen);

// 返回类实现的协议列表
Protocol * class_copyProtocolList(Class cls, unsigned int *outCount);
```

#### 7. 获取版本号

```c++
// 获取版本号 0表示类为非元类，7表示类为元类；
int class_getVersion(Class cls)
{
    if (!cls) return 0;
    assert(cls->isRealized());
    return cls->data()->version;
}

// 设置版本号
void class_setVersion ( Class cls, int version );
```

#### 8. 示例

通过示例来消化下上面的那些函数

```objc
//-----------------------------------------------------------
// MyClass.h
@interface MyClass : NSObject <NSCopying, NSCoding>
@property (nonatomic, strong) NSArray *array;
@property (nonatomic, copy) NSString *string;
- (void)method1;
- (void)method2;
+ (void)classMethod1;
@end

//-----------------------------------------------------------
// MyClass.m
#import "MyClass.h"
@interface MyClass () {
NSInteger _instance1;
NSString * _instance2;
}
@property (nonatomic, assign) NSUInteger integer;
- (void)method3WithArg1:(NSInteger)arg1 arg2:(NSString *)arg2;
@end

@implementation MyClass
+ (void)classMethod1 {}

- (void)method1 { NSLog(@"call method method1"); }

- (void)method2 { }

- (void)method3WithArg1:(NSInteger)arg1 arg2:(NSString *)arg2 {
     NSLog(@"arg1 : %ld, arg2 : %@", arg1, arg2);
}

@end

//-----------------------------------------------------------
// main.h

#import "MyClass.h"
#import "MySubClass.h"
#import <objc/runtime.h>

int main(int argc, const char * argv[]) {
     @autoreleasepool {
          MyClass *myClass = [[MyClass alloc] init];
          unsigned int outCount = 0;
          Class cls = myClass.class;
          // 类名
          NSLog(@"class name: %s", class_getName(cls));    
          NSLog(@"==========================================================");

          // 父类
          NSLog(@"super class name: %s", class_getName(class_getSuperclass(cls)));
          NSLog(@"==========================================================");

          // 是否是元类
          NSLog(@"MyClass is %@ a meta-class", (class_isMetaClass(cls) ? @"" : @"not"));
          NSLog(@"==========================================================");

          Class meta_class = objc_getMetaClass(class_getName(cls));
          NSLog(@"%s's meta-class is %s", class_getName(cls), class_getName(meta_class));
          NSLog(@"==========================================================");

          // 变量实例大小
          NSLog(@"instance size: %zu", class_getInstanceSize(cls));
          NSLog(@"==========================================================");

          // 成员变量
          Ivar *ivars = class_copyIvarList(cls, &outCount);
          for (int i = 0; i < outCount; i++) {
               Ivar ivar = ivars[i];
               NSLog(@"instance variable's name: %s at index: %d", ivar_getName(ivar), i);
          }

          free(ivars);

          Ivar string = class_getInstanceVariable(cls, "_string");
          if (string != NULL) {
               NSLog(@"instace variable %s", ivar_getName(string));
          }

          NSLog(@"==========================================================");

          // 属性操作
          objc_property_t * properties = class_copyPropertyList(cls, &outCount);
          for (int i = 0; i < outCount; i++) {
               objc_property_t property = properties[i];
               NSLog(@"property's name: %s", property_getName(property));
          }

          free(properties);

          objc_property_t array = class_getProperty(cls, "array");
          if (array != NULL) {
               NSLog(@"property %s", property_getName(array));
          }

          NSLog(@"==========================================================");

          // 方法操作
          Method *methods = class_copyMethodList(cls, &outCount);
          for (int i = 0; i < outCount; i++) {
               Method method = methods[i];
               NSLog(@"method's signature: %s", method_getName(method));
          }

          free(methods);

          Method method1 = class_getInstanceMethod(cls, @selector(method1));
          if (method1 != NULL) {
               NSLog(@"method %s", method_getName(method1));
          }

          Method classMethod = class_getClassMethod(cls, @selector(classMethod1));
          if (classMethod != NULL) {
               NSLog(@"class method : %s", method_getName(classMethod));
          }

          NSLog(@"MyClass is%@ responsd to selector: method3WithArg1:arg2:", class_respondsToSelector(cls, @selector(method3WithArg1:arg2:)) ? @"" : @" not");

          IMP imp = class_getMethodImplementation(cls, @selector(method1));
          imp();

          NSLog(@"==========================================================");

          // 协议
          Protocol * __unsafe_unretained * protocols = class_copyProtocolList(cls, &outCount);
          Protocol * protocol;
          for (int i = 0; i < outCount; i++) {
               protocol = protocols[i];
               NSLog(@"protocol name: %s", protocol_getName(protocol));
          }

          NSLog(@"MyClass is%@ responsed to protocol %s", class_conformsToProtocol(cls, protocol) ? @"" : @" not", protocol_getName(protocol));

          NSLog(@"==========================================================");
     }
     return 0;
}
```

输出结果

```objc
19:41:37.452 RuntimeTest class name: MyClass
19:41:37.453 RuntimeTest ====================================================
19:41:37.454 RuntimeTest super class name: NSObject
19:41:37.454 RuntimeTest ====================================================
19:41:37.454 RuntimeTest MyClass is not a meta-class
19:41:37.454 RuntimeTest ====================================================
19:41:37.454 RuntimeTest MyClass's meta-class is MyClass
19:41:37.455 RuntimeTest ====================================================
19:41:37.455 RuntimeTest instance size: 48
19:41:37.455 RuntimeTest ====================================================
19:41:37.455 RuntimeTest instance variable's name: _instance1 at index: 0
19:41:37.455 RuntimeTest instance variable's name: _instance2 at index: 1
19:41:37.455 RuntimeTest instance variable's name: _array at index: 2
19:41:37.455 RuntimeTest instance variable's name: _string at index: 3
19:41:37.463 RuntimeTest instance variable's name: _integer at index: 4
19:41:37.463 RuntimeTest instace variable _string
19:41:37.463 RuntimeTest ====================================================
19:41:37.463 RuntimeTest property's name: array
19:41:37.463 RuntimeTest property's name: string
19:41:37.464 RuntimeTest property's name: integer
19:41:37.464 RuntimeTest property array
19:41:37.464 RuntimeTest ====================================================
19:41:37.464 RuntimeTest method's signature: method1
19:41:37.464 RuntimeTest method's signature: method2
19:41:37.464 RuntimeTest method's signature: method3WithArg1:arg2:
19:41:37.465 RuntimeTest method's signature: integer
19:41:37.465 RuntimeTest method's signature: setInteger:
19:41:37.465 RuntimeTest method's signature: array
19:41:37.465 RuntimeTest method's signature: string
19:41:37.465 RuntimeTest method's signature: setString:
19:41:37.465 RuntimeTest method's signature: setArray:
19:41:37.466 RuntimeTest method's signature: .cxx_destruct
19:41:37.466 RuntimeTest method method1
19:41:37.466 RuntimeTest class method : classMethod1
19:41:37.466 RuntimeTest MyClass is responsd to selector: method3WithArg1:arg2:
19:41:37.467 RuntimeTest call method method1
19:41:37.467 RuntimeTest =====================================================
19:41:37.467 RuntimeTest protocol name: NSCopying
19:41:37.467 RuntimeTest protocol name: NSCoding
19:41:37.467 RuntimeTest MyClass is responsed to protocol NSCoding
19:41:37.468 RuntimeTest ======================================
```

### 2.6.3 动态创建类和对象

#### 1. 动态创建类

```c++
/* 
 * 创建一个新类和元类。Creates a new class and metaclass.
 * @prama superclass 如果创建的是root class，则superclass为Nil
 * @prama sextraBytes 通常为0
 */
Class objc_allocateClassPair(Class superclass, const char *name, size_t extraBytes);

// 创建新类后，使用class_addMethod，class_addIvar函数为新类添加方法、实例变量和属性。

// 在应用中注册由objc_allocateClassPair创建的类。再之后就能够用了。
void objc_registerClassPair(Class cls); 

// 销毁一个类及其相关联的类。在运行中还存在或存在子类实例，就不能够调用这个。
void objc_disposeClassPair(Class cls);
```

> 问题：什么是"class pair（类对）"？函数 objc_allocateClassPair 只返回一个值：类。那么这个"class pair（类对）"的另一半呢？从方法注释可以看出来，是元类。

使用示例

```objc
Class cls = objc_allocateClassPair(MyClass.class, "MySubClass", 0);
class_addMethod(cls, @selector(submethod1), (IMP)imp_submethod1, "v@:");
class_replaceMethod(cls, @selector(method1), (IMP)imp_submethod1, "v@:");
class_addIvar(cls, "_ivar1", sizeof(NSString *), log(sizeof(NSString *)), "i");

objc_property_attribute_t type = {"T", "@\"NSString\""};
objc_property_attribute_t ownership = { "C", "" };
objc_property_attribute_t backingivar = { "V", "_ivar1"};
objc_property_attribute_t attrs[] = {type, ownership, backingivar};

class_addProperty(cls, "property2", attrs, 3);
objc_registerClassPair(cls);

id instance = [[cls alloc] init];
[instance performSelector:@selector(submethod1)];
[instance performSelector:@selector(method1)];
```

输出

```objc
11:35:31.006 RuntimeTest[3800:66152] run sub method 1
11:35:31.006 RuntimeTest[3800:66152] run sub method 1
```

#### 2. 动态创建对象

```c++
// 创建类实例。会在heap里给类分配内存。这个方法和+alloc方法类似。
id class_createInstance(Class cls, size_t extraBytes)

// 在指定位置创建类实例
/*
 * 在bytes所指向的位置创建cls的实例。
 * bytes必须至少指向对齐的零填充内存的class_getInstanceSize(cls)字节。
 * 设置新对象的isa。调用任何c++构造函数。
 * 如果成功返回bytes。如果cls或bytes为nil，或c++构造函数失败，则返回nil。
 * 注意: class_createInstance()和class_createInstances()对此进行了预检。
 */
id objc_constructInstance(Class cls, void *bytes) 

// 销毁类实例
/*
 * 销毁实例而不释放内存。
 * 调用 C++ 析构函数。
 * 调用 ARC ivar 清理。
 * 移除除关联引用。
 * 返回obj。如果obj为nil，则什么都不做。
 */
void *objc_destructInstance(id obj) ; //不会释放移除任何相关引用
```

测试下效果

```objc
//可以看出class_createInstance和alloc的不同
id theObject = class_createInstance(NSString.class, sizeof(unsigned));
id str1 = [theObject init];
NSLog(@"%@", [str1 class]);
id str2 = [[NSString alloc] initWithString:@"test"];
NSLog(@"%@", [str2 class]);
```

输出结果

```objc
12:46:50.781 RuntimeTest[4039:89088] NSString
12:46:50.781 RuntimeTest[4039:89088] __NSCFConstantString
```

### 2.6.4 实例对象相关操作函数

这些函数是针对创建的实例对象的一系列操作函数。

#### 1. 操作 整个对象 的函数

```c++
// 返回指定对象的一份拷贝
id object_copy(id oldObj, size_t extraBytes);
// 释放指定对象占用的内存
id object_dispose(id obj);
```

应用场景

```objc
//把a转换成占用更多空间的子类b
NSObject *a = [[NSObject alloc] init];
id newB = object_copy(a, class_getInstanceSize(MyClass.class));
object_setClass(newB, MyClass.class);
object_dispose(a);
```

#### 2. 操作 对象的类 的函数

```c++
// 返回给定对象的类名
const char *object_getClassName(id obj);
// 返回对象的类
Class object_getClass(id obj);
// 设置对象的类
Class object_setClass(id obj, Class cls);
```

### 2.6.5 获取类定义

```c++
// 获取已注册的类定义的列表。返回值为已注册类的总数。
int objc_getClassList(Class *buffer, int bufferLen)

// 创建并返回一个指向所有已注册类的指针列表
Class *objc_copyClassList(unsigned int *outCount)

// 返回指定类的类定义
Class objc_lookUpClass(const char *aClassName);
Class objc_getClass(const char *aClassName);
Class objc_getRequiredClass(const char *aClassName); // 与objc_getClass相同，但如果没有找到类，则终止进程。

// 返回指定类的元类
Class objc_getMetaClass(const char *aClassName);
```

演示如何使用

```objc
int numClasses;
Class * classes = NULL;
numClasses = objc_getClassList(NULL, 0);

if (numClasses > 0) {
     classes = malloc(sizeof(Class) * numClasses);
     numClasses = objc_getClassList(classes, numClasses);
     NSLog(@"number of classes: %d", numClasses);

     for (int i = 0; i < numClasses; i++) {
          Class cls = classes[i];
          NSLog(@"class name: %s", class_getName(cls));
     }
     free(classes);
}
```


结果如下：

```objc
16:20:52.589 RuntimeTest[81] number of classes: 1282
16:20:52.589 RuntimeTest[81] class name: DDTokenRegexp
16:20:52.590 RuntimeTest[81] class name: _NSMostCommonKoreanCharsKeySet
16:20:52.590 RuntimeTest[81] class name: OS_xpc_dictionary
16:20:52.590 RuntimeTest[81] class name: NSFileCoordinator
16:20:52.590 RuntimeTest[81] class name: NSAssertionHandler
16:20:52.590 RuntimeTest[81] class name: PFUbiquityTransactionLogMigrator
16:20:52.591 RuntimeTest[81] class name: NSNotification
16:20:52.591 RuntimeTest[81] class name: NSKeyValueNilSetEnumerator
16:20:52.591 RuntimeTest[81] class name: OS_tcp_connection_tls_session
16:20:52.591 RuntimeTest[81] class name: _PFRoutines
......还有大量输出
```

# 三、成员变量、属性与关联对象

## 3.1 实例变量类型Ivar

> 实例变量是指在类的声明中，属性是用变量来表示的。 这种变量就称为实例变量，也叫对象变量、类成员变量；

### 3.1.1 Ivar结构

Ivar是指向 ivar_t 结构体的指针，ivar指针地址是根据class结构体的地址加上基地址偏移字节得到的。

```c++
struct ivar_t {
    int32_t *offset;   // 基地址偏移字节
    const char *name;  // 变量名
    const char *type;  // 变量类型
    // alignment is sometimes -1; use alignment() instead
    uint32_t alignment_raw;
    uint32_t size;
};

typedef struct ivar_t *Ivar;
```

```c++
// 获取成员变量的偏移量
ptrdiff_t ivar_getOffset(Ivar ivar);

// 获取成员变量的名称
const char *ivar_getName(Ivar ivar);

// 获取成员变量类型编码
const char *ivar_getTypeEncoding(Ivar ivar);
```

### 3.1.2 Ivar的获取和添加

```c++
// 获取整个成员变量列表(必须使用free()来释放这个数组)
Ivar *class_copyIvarList(Class cls, unsigned int *outCount)
  
// 添加成员变量(这个只能够向在runtime时创建的类添加成员变量)
// This function may only be called after objc_allocateClassPair and before objc_registerClassPair. 
// Adding an instance variable to an existing class is not supported.
BOOL class_addIvar(Class cls, const char *name, size_t size, uint8_t alignment, const char *type)
```

### 3.1.3 实例变量操作函数

```c++
// 修改类实例的实例变量的值
Ivar object_setInstanceVariable(id obj, const char *name, void *value);
// 获取对象实例变量的值
Ivar object_getInstanceVariable(id obj, const char *name, void **value);
// 返回指向给定对象分配的任何额外字节的指针
void *object_getIndexedIvars(id obj)
// 返回对象中实例变量的值
id object_getIvar(id obj, Ivar ivar);
// 设置对象中实例变量的值
void object_setIvar(id obj, Ivar ivar, id value);
```

## 3.2 属性类型property_t

### 3.2.1 property_t结构和objc_property_t

```c++
struct property_t {
    const char *name;       // property的名称
    const char *attributes; // property的属性
};

typedef struct property_t *objc_property_t;
```

属性attributes是一个字符串：`T<属性的类型>,[属性修饰符,[属性修饰符, ...]]V<实例变量名>`

- 该字符串以T开头
- 后面跟着属性的类型([Type Encodings](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html#//apple_ref/doc/uid/TP40008048-CH100-SW1))、属性修饰符（*见下图*），以逗号分隔。
- 然后是V，后面跟着实例变量的名称。(*官方文档 [Declared Properties](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtPropertyIntrospection.html#//apple_ref/doc/uid/TP40008048-CH101-SW24)，不过官方文档中的示例貌似有误或是过时，以下方示例为准*)

<img src="/images/runtime/02.png" alt="02" style="zoom:90%;" />

获取name、attributes的方法：

```c++
// 获取属性名
const char *property_getName(objc_property_t prop);

// 获取属性特性描述字符串
const char *property_getAttributes(objc_property_t prop);
```

### 3.2.2 property的获取和添加

获取类和协议的属性列表

```c++
/*
 * 返回一个包含类中声明的属性的堆块(heap block)，如果类没有声明属性，则返回nil。呼叫者必须释放区块。
 * 不复制任何超类的属性。
 */
objc_property_t *class_copyPropertyList(Class cls, unsigned int *outCount)

objc_property_t *protocol_copyPropertyList(Protocol *proto, unsigned int *outCount)
```

通过给出的名称来在类和协议中获取属性的引用:

```c++
objc_property_t class_getProperty(Class cls, const char *name);

objc_property_t protocol_getProperty(Protocol *proto, const char *name, BOOL isRequiredProperty, BOOL isInstanceProperty);
```

添加和修改：

```c++
/*
对于已经存在的类我们用class_addProperty方法来添加属性。
记得同时使用class_addMethod()添加setter和getter方法。但这样添加的属性没有对应的成员变量，所以得自己在setter和getter方法中决定数据的存取逻辑。
对于已经存在的类，class_addIvar是不能够添加属性的。class_addIvar只能为动态创建的类添加属性。
 */
void class_addProperty(Class _Nullable cls, const char * _Nonnull name,
                  const objc_property_attribute_t * _Nullable attributes,
                  unsigned int attributeCount);
void class_replaceProperty(Class _Nullable cls, const char * _Nonnull name,
                      const objc_property_attribute_t * _Nullable attributes,
                      unsigned int attributeCount);
```

### 3.2.3 property的特性attributes

objc_property_attribute_t也是结构体，定义属性的attribute

```c++
typedef struct {
     const char *name; // 特性名
     const char *value; // 特性值
} objc_property_attribute_t;

// 获取属性中指定的特性
char * property_copyAttributeValue(objc_property_t property, const char *attributeName);
// 获取属性的特性列表
objc_property_attribute_t *property_copyAttributeList(objc_property_t prop, 
                                                      unsigned int *outCount)
```

### 3.2.4 示例

```objc
@interface Lender : NSObject 
@property float alone;
@property char charDefault;
@property(nonatomic,readonly,copy)id idReadonlyCopyNonatomic;
@end

//获取属性列表
id LenderClass = objc_getClass("Lender");
unsigned int outCount, i;
objc_property_t *properties = class_copyPropertyList(LenderClass, &outCount);

for (i = 0; i < outCount; i++) {

    objc_property_t property = properties[i];
    fprintf(stdout, "%s %s\n", property_getName(property), property_getAttributes(property)); 

    unsigned int outCount2, j;
    objc_property_attribute_t * attries = property_copyAttributeList(property, &outCount2);
    for (j = 0; j < outCount2; j++) {
        objc_property_attribute_t attr = attries[j];
        fprintf(stdout, "%s %s\n", attr.name, attr.value);
    }
}

//输出
alone Tf,V_alone
T f
V _alone
  
charDefault Tc,V_charDefault
T c
V _charDefault
  
idReadonlyCopyNonatomic T@,R,C,N,V_idReadonlyCopyNonatomic
T @
R 
C 
N 
V _idReadonlyCopyNonatomic
```

## 3.3 关联对象

关联对象是在运行时添加的类似成员。

```c++
//设置对象 的一个关联对象
void objc_setAssociatedObject(id object, const void *key, id value, objc_AssociationPolicy policy);
  
//获取对象 指定的关联对象
id objc_getAssociatedObject(id object, const void *key);
  
//移除对象 所有关联对象
void objc_removeAssociatedObjects(id object);


//上面方法以键值对的形式动态的向对象添加，获取或者删除关联值。其中关联政策是一组枚举常量。这些常量对应着引用关联值机制，也就是Objc内存管理的引用计数机制。
enum {
     OBJC_ASSOCIATION_ASSIGN = 0,
     OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1,
     OBJC_ASSOCIATION_COPY_NONATOMIC = 3,
     OBJC_ASSOCIATION_RETAIN = 01401,
     OBJC_ASSOCIATION_COPY = 01403
};
```


示例：

```c++
//动态的将一个Tap手势操作连接到任何UIView中。
- (void)setTapActionWithBlock:(void (^)(void))block
{
     UITapGestureRecognizer *gesture = objc_getAssociatedObject(self, &kDTActionHandlerTapGestureKey);

     if (!gesture)
     {
          gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(__handleActionForTapGesture:)];
          [self addGestureRecognizer:gesture];
          //将创建的手势对象和block作为关联对象
          objc_setAssociatedObject(self, &kDTActionHandlerTapGestureKey, gesture, OBJC_ASSOCIATION_RETAIN);
     }

     objc_setAssociatedObject(self, &kDTActionHandlerTapBlockKey, block, OBJC_ASSOCIATION_COPY);
}

//手势识别对象的target和action
- (void)__handleActionForTapGesture:(UITapGestureRecognizer *)gesture
{
     if (gesture.state == UIGestureRecognizerStateRecognized)
     {
          void(^action)(void) = objc_getAssociatedObject(self, &kDTActionHandlerTapBlockKey);

          if (action)
          {
               action();
          }
     }
}
```

# 四、Method和消息

## 4.1 method_t、SEL和IMP

### 4.1.1 method_t结构和Method

method_t结构，用于表示类定义中的方法

```c++
struct method_t {
    SEL name;          // 方法名
    const char *types; // 编码，是个char指针，存储着方法的返回值类型、参数类型
    IMP imp;           // 指向函数实现的指针(函数地址)
};

typedef struct method_t *Method;
```

iOS中提供了一个叫做@encode的指令，可以将具体的类型表示成字符串编码。([Type Encodings](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html#//apple_ref/doc/uid/TP40008048-CH100-SW1))

```c++
- (void)test;
/*
   v16@0:8
   v - 返回值void
   @ - 参数1: id self
   : - 参数2: SEL _cmd
*/

- (int)test:(int)age height:(float)height;
/*
   i24@0:8i16f20
   i  - 返回值
   24 - 表示接下来的参数总共占多少个字节
   @  - 参数1: id self
   0  - 对应参数1，表示参数1的数据是从第几个字节开始的。后面的8 16 20分别对应参数234对应的开始位置
   :  - 参数2: SEL _cmd
   i  - 参数3: int
   f  - 参数4: float
*/
```

### 4.1.2 SEL

```c++
// SEL代表方法\函数名，一般叫做选择器，底层结构跟char *类似.(可以简单的理解为是个字符串).
  // 可以通过@selector()和sel_registerName()获得.
  // 可以通过sel_getName()和NSStringFromSelector()转成字符串.
  // 不同类中相同名字的方法，所对应的方法选择器是相同的.
typedef struct objc_selector *SEL;
```

```c++
//objc_selector编译时会根据每个方法名字参数序列生成唯一标识
SEL sel1 = @selector(load);
NSLog(@"sel : %p", sel1);

//输出
18:40:07.518 RuntimeTest[52:46] sel : 0x7fff606203c3
```

### 4.1.3 IMP

是函数指针，指向方法的首地址，得到了IMP，就可以跳过Runtime消息传递机制直接执行函数，比直接向对象发消息高效。定义如下

```c++
// IMP代表函数的具体实现
typedef id _Nullable (*IMP)(id _Nonnull, SEL _Nonnull, ...);
```

## 4.2 Method相关操作函数

### 4.2.1 获取Method的信息

```c++
// 获取方法名。如果希望获得方法明的C字符串，使用sel_getName(method_getName(method))
SEL method_getName(Method m);
// 返回方法的实现
IMP method_getImplementation(Method m);

// 获取描述方法参数和返回值类型的字符串
const char *method_getTypeEncoding(Method m);
// 获取方法的返回值类型的字符串
char * method_copyReturnType(Method m);
// 获取方法的返回值类型的字符串：通过引用返回，这种参数又称为传出参数
void method_getReturnType(Method m, char *dst, size_t dst_len);

// 返回方法的参数的个数
unsigned int method_getNumberOfArguments(Method m);
// 获取方法的指定位置参数的类型字符串
char * method_copyArgumentType(Method m, unsigned int index);
// 获取方法的指定位置参数的类型字符串：通过引用返回
void method_getArgumentType(Method m, unsigned int index, char *dst, size_t dst_len);

// 返回指定方法的方法描述结构体
struct objc_method_description {
    SEL _Nullable name;               /**< The name of the method */
    char * _Nullable types;           /**< The types of the method arguments */
};
struct objc_method_description *method_getDescription(Method m);
```

### 4.2.2 获取和设置Method的IMP

```c++
// 设置方法的实现
IMP method_setImplementation(Method m, IMP imp);

// 交换两个方法的实现
void method_exchangeImplementations(Method m1, Method m2);
```

NSObject提供了一个methodForSelector:方法可以获得Method的IMP指针，通过指针调用实现代码。

```c++
+ (IMP)instanceMethodForSelector:(SEL)sel;
+ (IMP)methodForSelector:(SEL)sel;
- (IMP)methodForSelector:(SEL)sel;
```

示例：

```objc
void (*setter)(id, SEL, BOOL);
int i;
setter = (void (*)(id, SEL, BOOL))[target methodForSelector:@selector(setFilled:)];
for(i = 0; i < 1000; i++)
    setter(targetList[i], @selector(setFilled:), YES);
```

### 4.2.3 直接调用Method

```c++
// 调用指定方法的实现，返回的是方法实现时的返回，参数receiver不能为空，这个比method_getImplementation和method_getName快
id method_invoke(id receiver, Method m, ... );
// 调用 (返回一个数据结构的) 方法的实现
void method_invoke_stret(id receiver, Method m, ...) 
```

### 4.2.4 SEL的操作函数

```c++
// 返回给定选择器指定的方法的名称
const char *sel_getName(SEL sel);
// 在objectivec Runtime系统中注册一个方法，将方法名映射到一个选择器，并返回这个选择器
SEL sel_registerName(const char *name);
// 在objectivec Runtime系统中注册一个方法
SEL sel_getUid(const char *name);
// 比较两个选择器
BOOL sel_isEqual(SEL lhs, SEL rhs); // Lhs --> Left Hand Side，也就是算式左边的意思
```

## 4.3 Method调用流程objc_msgSend

消息函数，Objc中发送消息是用中括号把接收者和消息括起来，只到运行时才会把消息和方法实现绑定。

OC中的方法调用，其实都是转换为下面几个函数的调用。编译器会根据情况在objc_msgSend，objc_msgSend_stret，objc_msgSendSuper，或objc_msgSendSuper_stret四个方法中选一个调用。

- 如果是传递给超类就会调用带super的函数；
- 如果返回是数据结构而不是一个值就会调用带stret的函数；
- 在i386平台返回类型为浮点消息会调用objc_msgSend_fpret函数。
```c++
// 这个函数将消息接收者和方法名(选择器)作为基础参数。
   // 使用self关键字来引用实例本身，self的内容即接收消息的对象是在Method运行时被传入
   // 还有方法选择器
id objc_msgSend(id _Nullable self, SEL _Nonnull op, ...)
```

### 流程概述

objc_msgSend的执行流程可以分为3大阶段：消息发送、动态方法解析、消息转发

```objc
#pragma mark -- 消息发送阶段
//在objc-msg-arm64.s中
▼ _objc_msgSend
  ▼ CacheLookup  // 缓存查找
    ▼ CheckMiss // 如果缓存没有命中
      ▼ __objc_msgSend_uncached
        ▼ MethodTableLookup
        // 其中有一行 bl __class_lookupMethodAndLoadCache3. 此时在objc-msg-arm64.s已经查不到该方法了。前缀减去
        // 一个_（符号修饰）然后全局搜索，可以在objc-runtime-new.mm中找到该方法_class_lookupMethodAndLoadCache3
//objc-runtime-new.mm
  ▼ _class_lookupMethodAndLoadCache3
  	/*
  	 // 仅用于汇编中的方法查找。其他代码应该使用lookUpImp()。这种查找避免了乐观的缓存扫描，因为汇编中已经尝试过。
  	 IMP _class_lookupMethodAndLoadCache3(id obj, SEL sel, Class cls){
  	      // NO是cache. cache==NO跳过乐观的解锁查找(但在其他地方使用缓存);
          return lookUpImpOrForward(cls, sel, obj, YES, NO, YES);
     }
  	 */
    ▼ lookUpImpOrForward
      ▶ cache_getImp            // 查找当前类的cache
      ▶ getMethodNoSuper_nolock // 查找当前类的methods
      ▶ cache_getImp            // 查找父类(父类的父类...)的cache
      ▶ getMethodNoSuper_nolock // 查找父类(父类的父类...)的methods
        ▼ search_method_list
          ▶ findMethodInSortedMethodList  //若有序，二分查找
          ▶ //若无序，线性查找
      ▼ log_and_fill_cache  // 不管是在本类、父类、基类中找到的，只要不在本类的cache中，就填充缓存
        ▼ cache_fill
          ▶ cache_fill_nolock

#pragma mark -- 动态方法解析
      ▼ _class_resolveMethod      // 动态方法解析. 在运行时(动态)向特定类添加特定方法实现。
        ▶ _class_resolveClassMethod    // 如果是元类对象，调用类的该类方法(需要自己实现)，在该方法中，将要调用的方法添加到class/meta-class中。见MJPerson.m
        ▶ _class_resolveInstanceMethod // 如果是类对象，同上...
        //..动态解析过后，会重新走“消息发送”的流程

#pragma mark -- 消息转发
      ▶ _objc_msgForward_impcache // 消息转发. No implementation found, and method resolver didn't help. Use forwarding.
```

大致流程图如下：

<img src="/images/runtime/03.png" alt="03" style="zoom:80%;" />

### 4.3.1 消息发送

- 消息发送给一个对象时，objc_msgSend通过对象的isa指针获得类的结构体，先在Cache里找，找到就执行
- 没找到就在分发列表里查找方法的selector
- 没找到就通过objc_class结构体中指向父类的指针找到父类，然后在父类分发列表找
- 直到root class（NSObject）

如果root class仍然找不到方法，不会直接报错，会进入以下两个补救阶段。不过安全起见，一些场景中，可以先添加方法能否响应的判断：

```objc
//先调用respondsToSelector:来判断一下
if ([self respondsToSelector:@selector(method)]) {
     [self performSelector:@selector(method)];
}
```

### 4.3.2 动态方法解析

```objc
void functionForMethod1(id self, SEL _cmd) {
     NSLog(@"%@, %p", self, _cmd);
}

+ (BOOL)resolveInstanceMethod:(SEL)sel {
     NSString *selectorString = NSStringFromSelector(sel);
     if ([selectorString isEqualToString:@"method1"]) {
          class_addMethod(self.class, @selector(method1), (IMP)functionForMethod1, "@:");
     }
     return [super resolveInstanceMethod:sel];
}
```

可以动态的提供一个方法的实现。例如可以用@dynamic关键字在类的实现文件中写个属性

```objc
//这个表明会为这个属性动态提供set get方法，就是编译器是不会默认生成setPropertyName:和propertyName方法，需要动态提供。
@dynamic propertyName;

void dynamicMethodIMP(id self, SEL _cmd) {
     // implementation ....
}

@implementation MyClass
/**
 如果是对象方法找不到，动态方法解析 会调用+(BOOL)resolveInstanceMethod:(SEL)sel
 如果是类方法找不到， 动态方法解析 会调用+(BOOL)resolveClassMethod:(SEL)sel
 */
+ (BOOL)resolveInstanceMethod:(SEL)sel{}
  
+ (BOOL)resolveClassMethod:(SEL)sel
{
    if (sel == @selector(resolveThisMethodDynamically)) {
        //v@:表示返回值和参数，可以在苹果官网查看Type Encoding相关文档 https://developer.apple.com/library/mac/DOCUMENTATION/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
        // 最后用class_addMethod完成添加特定方法实现的操作
        class_addMethod([self class], sel, (IMP)dynamicMethodIMP, "v@:");
        return YES;
    }
    return [super resolveInstanceMethod:sel];
}
@end
```

### 4.3.3 消息转发

#### 1. 重定向接收者

如果无法处理消息会继续调用下面的方法，同时在这里Runtime系统实际上是给了一个替换消息接收者的机会，但是替换的对象千万不要是self，那样会进入死循环。

```objc
// 使用这个方法通常在对象内部

// 如果是实例方法
- (id)forwardingTargetForSelector:(SEL)aSelector
{
     // 将消息转发给alternateObject来处理
     if(aSelector == @selector(mysteriousMethod:)){
          return alternateObject;
     }
     return [super forwardingTargetForSelector:aSelector];
}

// 如果是类方法
+ (id)forwardingTargetForSelector:(SEL)aSelector{
   // 这个return，不仅限于类对象，也可以是实例对象，前提是这个实例对象有名为aSelector的实例方法。因为前面已经说了，底层代码得到return的对象后，就会调用objc_msgSend，如果返回的实例对象，就相当于objc_msgSend(obj, @selector(test))，最后是能完成消息发送的
   return obj;
}
```

#### 2. 最后进行转发

如果以上两种都没法处理未知消息就需要完整消息转发了。调用如下方法

```objc
//必须重写这个方法，消息转发使用这个方法获得的信息创建NSInvocation对象。如果没有实现，或者返回nil，消息转发结束。
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector;

//这一步是最后机会将消息转发给其它对象，对象会将未处理的消息相关的selector，target和参数都封装在anInvocation中。forwardInvocation:像未知消息分发中心，将未知消息转发给其它对象。注意的是forwardInvocation:方法只有在消息接收对象无法正常响应消息时才被调用。
- (void)forwardInvocation:(NSInvocation *)anInvocation;

//如果是类方法
+ (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector;
+ (void)forwardInvocation:(NSInvocation *)anInvocation;
```


范例

```objc
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
     NSMethodSignature *signature = [super methodSignatureForSelector:aSelector];

     if (!signature) {
          if ([SUTRuntimeMethodHelper instancesRespondToSelector:aSelector]) {
               signature = [SUTRuntimeMethodHelper instanceMethodSignatureForSelector:aSelector];
          }
     }
     return signature;
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
     if ([SUTRuntimeMethodHelper instancesRespondToSelector:anInvocation.selector]) {
          [anInvocation invokeWithTarget:_helper];
     }
}
```

### 4.3.4 消息转发和多继承

OC是否支持多继承？有没有模拟多继承特性的办法？

转发和继承相似，一个Object把消息转发出去就好像它继承了另一个Object的方法一样。

消息转发弥补了objc不支持多继承的性质，也避免了因为多继承导致单个类变得臃肿复杂。

虽然转发可以实现继承功能，但是NSObject还是必须表面上很严谨，像`respondsToSelector:`和`isKindOfClass:`这类方法只会考虑继承体系，不会考虑转发链。

### 4.3.5 Message消息的参考文章

- [Message forwarding](https://mikeash.com/pyblog/friday-qa-2009-03-27-objectivec-message-forwarding.html)
- [objectivec messaging](https://www.mikeash.com/pyblog/friday-qa-2009-03-20-objectivec-messaging.html)
- [The faster objc_msgSend](http://www.mulle-kybernetik.com/artikel/Optimization/opti-9.html)

## 4.4 super和objc_msgSendSuper

`NSStringFromClass([self class])` 和 `NSStringFromClass([super class])` 输出都是self的类名。原因如下：

```c++
// [super message]的底层实现:
// super调用，底层会转换为objc_msgSendSuper2函数的调用，接收2个参数
struct objc_super2 {
   id receiver;         // receiver是self，表示消息接收者仍然是子类对象
   Class current_class; // 会从父类current_class.superclass开始查找方法的实现
};
SEL
```

```c++
/**
 * Sends a message with a simple return value to the superclass of an instance of a class.
 *
 * @param super 指向objc_super数据结构的指针。传递消息发送的上下文的值，包括要接收消息的类的实例和开始搜索方法实现的超类。including the instance of the class that is to receive the message and the superclass at which to start searching for the method implementation。
 * 由此可知，消息仍然是receiver来处理，superclass指定了`消息发送`阶段，方法从isa->superclass->superclass.superclass...->NSObject链中superclass为起点开始向上寻找。
 *
 * @param op   SEL类型的指针。传递将处理消息的方法的选择器。
 * @param ...  A variable argument list containing the arguments to the method.
 * @return     The return value of the method identified by \e op.
 * @see objc_msgSend
 */
id objc_msgSendSuper(struct objc_super * _Nonnull super, SEL _Nonnull op, ...);
id objc_msgSendSuper2(struct objc_super * _Nonnull super, SEL _Nonnull op, ...);
```

结论：super只是改变了方法查找链的起始位置，调用者是不变的。

## 4.5 Method Swizzling

是改变一个selector实际实现的技术，可以在运行时修改selector对应的函数来修改Method的实现。前面的消息转发很强大，但是需要能够修改对应类的源码，但是对于有些类无法修改其源码时又要更改其方法实现时可以使用Method Swizzling，通过重新映射方法来达到目的，但是跟消息转发比起来调试会困难。

### 4.5.1 使用method swizzling需要注意的问题

- **Swizzling应该总在+load中执行**：objectivec在运行时会自动调用类的两个方法+load和+initialize。+load会在类初始加载时调用，和+initialize比较+load能保证在类的初始化过程中被加载。
  - Swizzling在+load中执行时，不要调用[super load]。原因同下面一条，如果是多继承，并且对同一个方法都进行了Swizzling（*没有在dispatch_once中执行*），那么调用[super load]以后，父类的Swizzling就失效了。
- **Swizzling应该总是在dispatch_once中执行**：swizzling会改变全局状态，所以在运行时采取一些预防措施，使用dispatch_once就能够确保代码不管有多少线程都只被执行一次。这将成为method swizzling的最佳实践。
  - 如果不写dispatch_once，偶数次交换以后，相当于没有交换，Swizzling失效！
- **Swizzling时，需要注意class_getInstanceMethod的特性**：该方法的实现中，如果这个类中没有实现selector这个方法，那么它会沿着继承链找到为止，即其可能返回的是它某父类的Method对象。所以提前判断很重要，避免错误的交换了父类中的方法。
- 交换的分类方法应尽量调用原实现。
  - 很多情况我们不清楚被交换的的方法具体做了什么内部逻辑，而且很多被交换的方法都是系统封装的方法，所以为了保证其逻辑性都应该在分类的交换方法中去调用原被交换方法。
  - 注意：调用时方法交换已经完成，在分类方法中应该调用分类方法本身才正确。
  - 作用：比如之前a应该和b互换了方法，c方法在不知情的状况下和a互换了方法。只有在交换的方法中调用原实现，才能保证c→b→a中的代码都能得到执行。


### 4.5.2 实现一

举例说明如何使用Method Swizzling对一个类中注入一些我们的新的操作。

```objc
#import <objc/runtime.h>

@implementation UIViewController (Tracking)

+ (void)load {
     static dispatch_once_t onceToken;
     dispatch_once(&onceToken, ^{
          Class class = [self class];
          // When swizzling a class method, use the following:
          // Class class = object_getClass((id)self);
          
          //通过method swizzling修改了UIViewController的@selector(viewWillAppear:)的指针使其指向了自定义的xxx_viewWillAppear
          SEL originalSelector = @selector(viewWillAppear:);
          SEL swizzledSelector = @selector(xxx_viewWillAppear:);

          Method originalMethod = class_getInstanceMethod(class, originalSelector);
          Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);

          BOOL didAddMethod = class_addMethod(class,
               originalSelector,
               method_getImplementation(swizzledMethod),
               method_getTypeEncoding(swizzledMethod));
          
          //如果类中不存在要替换的方法，就先用class_addMethod和class_replaceMethod函数添加和替换两个方法实现。但如果已经有了要替换的方法，就调用method_exchangeImplementations函数交换两个方法的Implementation。
          if (didAddMethod) {
               class_replaceMethod(class,
                    swizzledSelector,
                    method_getImplementation(originalMethod),
                    method_getTypeEncoding(originalMethod));
          } else {
               method_exchangeImplementations(originalMethod, swizzledMethod);
          }
     });
}

#pragma mark - Method Swizzling
- (void)xxx_viewWillAppear:(BOOL)animated {
     [self xxx_viewWillAppear:animated];
     NSLog(@"viewWillAppear: %@", self);
}

@end
```


method_exchangeImplementations做的事情和如下代码是一样的

```c++
IMP imp1 = method_getImplementation(m1);
IMP imp2 = method_getImplementation(m2);
method_setImplementation(m1, imp2);
method_setImplementation(m2, imp1);
```

### 4.5.3 实现二

```objc
+ (void) load{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method originalMethod = class_getInstanceMethod([self class], @selector(xxxx));
        Method swizzledMethod = class_getInstanceMethod([self class], @selector(x_xxxxx));
        // 判断两个方法是不是空，本类和父类都找不到则直接return
        if (!originalMethod || !swizzledMethod) return;
        // 不管方法在不在本类，都执行class_addMethod方法，最后的结果是本类中两个方法都存在了，这样也不用管他们有没有被交换过。
        class_addMethod([self class], method_getName(originalMethod), method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
        class_addMethod([self class], method_getName(swizzledMethod), method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
        // 交换，此时就不用再考虑本类父类的逻辑
        method_exchangeImplementations(originalMethod, swizzledMethod);
    });
}
```

### 4.5.4 错误实现

#### 1. 不加判断直接exchange

```objc
@interface Base : NSObject
- (void)basePrint;
@end
@implementation Base
- (void)basePrint{
    NSLog(@"%s",__func__);
}
@end

@interface B : Base
@end
@implementation B
@end
  
@interface A : NSObject
- (void)APrint;
@end
@implementation A
+ (void)load{
    Class cls = [B class];
    Method originalMethod = class_getInstanceMethod(cls, @selector(basePrint));
    Method swizzledMethod = class_getInstanceMethod([self class], @selector(APrint));
    //这种不加判断的交换是不合理的。直接将父类的方法实现交换了
    method_exchangeImplementations(originalMethod, swizzledMethod);
}
- (void)APrint{
    NSLog(@"%s",__func__);
}
@end
```

#### 2. 错误使用class_replaceMethod

```objectivec
+ (void) load{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method originalMethod = class_getInstanceMethod([self class], @selector(xxxx));
        Method swizzledMethod = class_getInstanceMethod([self class], @selector(x_xxxxx));
// ===== 错误一：如果本类中已有实现
        class_replaceMethod([self class],
                          method_getName(originalMethod),
                          method_getImplementation(swizzledMethod),
                          method_getTypeEncoding(swizzledMethod));
        class_replaceMethod([self class],
                          method_getName(swizzledMethod),
                          //此时originalMethod已经被replace imp了，即其imp，实际上已经是swizzledMethod的IMP了
                          method_getImplementation(originalMethod), 
                          method_getTypeEncoding(originalMethod));
// ===== 错误二：如果本类中没有实现
        // 当cls中此时没有origSelector的实现时，那class_replaceMethod实质上是class_addMethod，返回值为NULL
        IMP previousIMP = class_replaceMethod([self class],
                                      method_getName(originalMethod),,
                                      method_getImplementation(swizzledMethod),
                                      method_getTypeEncoding(swizzledMethod));
        // 如果previousIMP，那么replaceMethod失败，即保持原样。
        class_replaceMethod([self class],
                            method_getName(swizzledMethod),,
                            previousIMP,
                            method_getTypeEncoding(originalMethod));
    });
}
```

这里有几个关于Method Swizzling的资源可以参考

- [How do I implement method swizzling?](http://stackoverflow.com/questions/5371601/how-do-i-implement-method-swizzling)
- [Method Swizzling](http://nshipster.com/method-swizzling/)
- [What are the Dangers of Method Swizzling in Objective C?](http://stackoverflow.com/questions/5339276/what-are-the-dangers-of-method-swizzling-in-objectivec)
- [JRSwizzle](https://github.com/rentzsch/jrswizzle)

# 五、Category和Protocol

## 5.1 分类Category

### 5.1.1 分类概述

Category是Objective-C 2.0之后添加的语言特性。

Category 有那些用途？

- 主要作用是为已经存在的类添加方法。常见的是给系统类添加方法、属性（需要关联对象）。
- 除此之外，apple还推荐了category的另外两个使用场景：[官方文档](https://developer.apple.com/library/ios/documentation/General/Conceptual/DevPedia-CocoaCore/Category.html)
  - 可以把类的实现分开在几个不同的文件里面。这样做有几个显而易见的好处：
    - 可以减少单个文件的体积 
    - 可以把不同的功能组织到不同的category里，实现按照不同的特性归类。
    - 可以由多个开发者共同完成一个类
    - 可以按需加载想要的category 等等。
  - 声明私有方法：为在.m文件中实现的方法，添加声明，使得外部可以调用。

不过除了apple推荐的使用场景，广大开发者脑洞大开，还衍生出了category的其他几个使用场景：

- 模拟多继承
- 把framework的私有方法公开

Objective-C的这个语言特性对于纯动态语言来说可能不算什么，比如javascript，你可以随时为一个“类”或者对象添加任意方法和实例变量。但是对于不是那么“动态”的语言而言，这确实是一个了不起的特性。

### 5.1.2 category_t结构和Category

指向分类的结构体的指针

```c++
struct category_t {
    const char *name;  // 是指 class_name 而不是 category_name
    classref_t cls;    // 指向扩展的类对象，编译期间是不会定义的，而是在Runtime阶段通过name对应到对应的类对象
    struct method_list_t *instanceMethods; // 实例方法列表
    struct method_list_t *classMethods;    // 类方法列表，Meta Class方法列表的子集
    struct protocol_list_t *protocols;     // 分类所实现的协议列表
    struct property_list_t *instanceProperties;  // category中添加的所有属性
    // Fields below this point are not always present on disk.
    struct property_list_t *_classProperties;
};

typedef struct category_t *Category;
```

从category的定义也可以看出category的：

- 可为 (可以添加实例方法，类方法，甚至可以实现协议，添加属性(属性添加、使用，编译是能通过的，运行会crash))
- 不可为 (无法添加实例变量）
  - 编译后的类已经注册在runtime中，类结构体中的 ivars (实例变量的链表) 和 instance_size (实例变量的内存大小) 已经确定。
  - category_t 中并没有空间来存放类的成员变量Ivar。

Category里面的方法加载过程，objc源码中找到objc-os.mm，函数`_objc_init`就是runtime的加载入口由libSystem调用，开始初始化，之后objc-runtime-new.mm里的map_images会加载map到内存，`_read_images`开始初始化这个map，这时会load所有Class，Protocol和Category，NSObject的+load方法就是这个时候调用的。

### 5.1.3 示例：分类的编译

Lender+TT.h

```objc
#import "Lender.h"
NS_ASSUME_NONNULL_BEGIN

@interface Lender (TT)
@property (nonatomic, strong) NSString * lxyname;

- (void)test;
@end
```

Lender+TT.m

```objc
#import "Lender+TT.h"
@implementation Lender (TT)

- (void)test{
    NSLog(@"xxxxxxxx");
}

@end
```

使用clang的命令去看看category到底会变成什么(主要是看一下分类中的属性底层是什么)：

```c++
//方法列表
static struct /*_method_list_t*/ {
	unsigned int entsize;  // sizeof(struct _objc_method)
	unsigned int method_count;
	struct _objc_method method_list[1];
} _OBJC_$_CATEGORY_INSTANCE_METHODS_Lender_$_TT __attribute__ ((used, section ("__DATA,__objc_const"))) = {
	sizeof(_objc_method),
	1,
	{{(struct objc_selector *)"test", "v16@0:8", (void *)_I_Lender_TT_test}}
};

//属性列表
static struct /*_prop_list_t*/ {
	unsigned int entsize;  // sizeof(struct _prop_t)
	unsigned int count_of_properties;
	struct _prop_t prop_list[1];
} _OBJC_$_PROP_LIST_Lender_$_TT __attribute__ ((used, section ("__DATA,__objc_const"))) = {
	sizeof(_prop_t),
	1,
	{{"lxyname","T@\"NSString\",&,N"}}
};

extern "C" __declspec(dllimport) struct _class_t OBJC_CLASS_$_Lender;

//分类
static struct _category_t _OBJC_$_CATEGORY_Lender_$_TT __attribute__ ((used, section ("__DATA,__objc_const"))) = 
{
	"Lender",
	0, // &OBJC_CLASS_$_Lender,
	(const struct _method_list_t *)&_OBJC_$_CATEGORY_INSTANCE_METHODS_Lender_$_TT,
	0,
	0,
	(const struct _prop_list_t *)&_OBJC_$_PROP_LIST_Lender_$_TT,  //属性列表
};

// 运行时期给分类结构的.cls赋值
static void OBJC_CATEGORY_SETUP_$_Lender_$_TT(void ) {
	_OBJC_$_CATEGORY_Lender_$_TT.cls = &OBJC_CLASS_$_Lender;
}

#pragma section(".objc_inithooks$B", long, read, write)
__declspec(allocate(".objc_inithooks$B")) static void *OBJC_CATEGORY_SETUP[] = {
	(void *)&OBJC_CATEGORY_SETUP_$_Lender_$_TT,
};
static struct _category_t *L_OBJC_LABEL_CATEGORY_$ [1] __attribute__((used, section ("__DATA, __objc_catlist,regular,no_dead_strip")))= {
	&_OBJC_$_CATEGORY_Lender_$_TT,
};
static struct IMAGE_INFO { unsigned version; unsigned flag; } _OBJC_IMAGE_INFO = { 0, 2 };
```

我们可以看到：

1. 首先编译器生成了实例方法列表 `_OBJC_$_CATEGORY_INSTANCE_METHODS_Lender_$_TT` 和属性列表 `_OBJC_$_PROP_LIST_Lender_$_TT`，两者的命名都遵循了公共前缀+类名+category名字的命名方式，而且实例方法列表里面填充的正是我们在 `TT` 这个category里面写的方法 `test`，而属性列表里面填充的也正是我们在 `TT` 里添加的 `lxyname` 属性。还有一个需要注意到的事实就是category的名字用来给各种列表以及后面的category结构体本身命名，而且有static来修饰，所以在同一个编译单元里我们的category名不能重复，否则会出现编译错误。

2. 其次，编译器生成了category本身 `_OBJC_$_CATEGORY_Lender_$_TT`，并用前面生成的列表来初始化category本身。

3. 最后，编译器在**DATA segment(段)下的objc_catlist section(节)** 里保存了一个大小为1的category_t的数组`L_OBJC_LABEL_CATEGORY_$`（当然，如果有多个category，会生成对应长度的数组^_^），用于运行期category的加载。

### 5.1.4 分类的运行时处理

见[dyld与Runtime—_objc_init、map_images、load_images的4.2小节：分类的加载](https://tenloy.github.io/2021/10/21/dyld-objc.html#4-2-loadAllCategories-%E5%88%86%E7%B1%BB%E5%8A%A0%E8%BD%BD)

## 5.2 类扩展(Extension)

extension看起来很像一个匿名的category，但是extension和有名字的category几乎完全是两个东西。 

extension在编译期决议，它就是类的一部分，在编译期和头文件里的@interface以及实现文件里的@implement一起形成一个完整的类，它伴随类的产生而产生，亦随之一起消亡。extension一般用来隐藏类的私有信息，你必须有一个类的源码才能为一个类添加extension，所以你无法为系统的类比如NSString添加extension。（详见官方文档[Customizing Existing Classes](https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ProgrammingWithObjectiveC/CustomizingExistingClasses/CustomizingExistingClasses.html)）

但是category则完全不一样，它是在运行期决议的。可以为系统 framework、第三方框架等添加 category。 

就category和extension的区别来看，我们可以推导出一个明显的事实，extension可以添加实例变量，而category是无法添加实例变量的（因为在运行期，对象的内存布局已经确定，如果添加实例变量就会破坏类的内部布局，这对编译型语言来说是灾难性的）。

## 5.3 Protocol

Protocol其实就是一个对象结构体

```c++
typedef struct objc_object Protocol;
```

## 5.4 操作函数

### 5.4.1 Category操作函数

Category操作函数信息都包含在objc_class中，我们可以通过objc_class的操作函数来获取分类的操作函数信息。

```objc
@interface RuntimeCategoryClass : NSObject
- (void)method1;
@end

@interface RuntimeCategoryClass (Category)
- (void)method2;
@end

@implementation RuntimeCategoryClass
- (void)method1 {}
@end

@implementation RuntimeCategoryClass (Category)
- (void)method2 {}
@end

#pragma mark -
NSLog(@"测试objc_class中的方法列表是否包含分类中的方法");
unsigned int outCount = 0;
Method *methodList = class_copyMethodList(RuntimeCategoryClass.class, &outCount);

for (int i = 0; i < outCount; i++) {
     Method method = methodList[i];

     const char *name = sel_getName(method_getName(method));

     NSLog(@"RuntimeCategoryClass's method: %s", name);

     if (strcmp(name, sel_getName(@selector(method2)))) {
          NSLog(@"分类方法method2在objc_class的方法列表中");
     }
}

//输出
2014-11-08 10:36:39.213 [561:151847] 测试objc_class中的方法列表是否包含分类中的方法
2014-11-08 10:36:39.215 [561:151847] RuntimeCategoryClass's method: method2
2014-11-08 10:36:39.215 [561:151847] RuntimeCategoryClass's method: method1
2014-11-08 10:36:39.215 [561:151847] 分类方法method2在objc_class的方法列表中
```

### 5.4.2 Protocol操作函数

Runtime提供了Protocol的一系列函数操作，函数包括：

#### 1. 获取协议

```c++
// 返回指定的协议
Protocol *objc_getProtocol(const char *name);

// 获取运行时所知道的所有协议的数组
Protocol **objc_copyProtocolList(unsigned int *outCount);
```

#### 2. 查询协议的信息

```c++
// 返回协议名
const char *protocol_getName(Protocol *proto);

// 测试两个协议是否相等
BOOL protocol_isEqual(Protocol *self, Protocol *other);

// 获取协议中指定条件的方法描述数组
struct objc_method_description *protocol_copyMethodDescriptionList(Protocol *p, 
                                   BOOL isRequiredMethod,BOOL isInstanceMethod,
                                   unsigned int *outCount);

// 获取协议中指定方法的方法描述
struct objc_method_description protocol_getMethodDescription(Protocol *p, SEL aSel, 
                              BOOL isRequiredMethod, BOOL isInstanceMethod);

// 获取协议中的属性列表
objc_property_t *protocol_copyPropertyList(Protocol *proto, unsigned int *outCount);

// 获取协议的指定属性
objc_property_t protocol_getProperty(Protocol *p, const char *name, 
                              BOOL isRequiredProperty, BOOL isInstanceProperty);
// 获取协议遵守的协议
Protocol ** protocol_copyProtocolList(Protocol *p, unsigned int *outCount);

// 查看协议是否遵守了另一个协议
BOOL protocol_conformsToProtocol(Protocol *self, Protocol *other);
```

#### 3. 动态创建协议

```c++
// 创建新的协议实例
Protocol *objc_allocateProtocol(const char *name);

// 为协议添加方法
void protocol_addMethodDescription(Protocol *proto_gen, SEL name, const char *types,
                              BOOL isRequiredMethod, BOOL isInstanceMethod);

// 为协议添加属性 
void protocol_addProperty(Protocol *proto_gen, const char *name, 
                     const objc_property_attribute_t *attrs, 
                     unsigned int count,
                     BOOL isRequiredProperty, BOOL isInstanceProperty);

// 为协议添加一个已注册的协议。proto必须正在构造中。addition则不能，必须是已注册的。
void protocol_addProtocol(Protocol *proto, Protocol *addition);

// 在运行时中注册新创建的协议。
// 创建一个新协议后必须使用这个进行注册这个新协议，但是注册后不能够再修改和添加新方法。
void objc_registerProtocol(Protocol *proto_gen);
```

# 六、Block

runtime中一些支持block操作的函数

```c++
// 创建一个指针函数的指针，该函数调用时会调用特定的block
IMP imp_implementationWithBlock(id block);

// 返回与IMP(使用imp_implementationWithBlock创建的)相关的block
id imp_getBlock(IMP anImp);

// 解除block与IMP(使用imp_implementationWithBlock创建的)的关联关系，并释放block的拷贝
BOOL imp_removeBlock(IMP anImp);
```


测试代码

```objc
@interface MyRuntimeBlock : NSObject
@end
@implementation MyRuntimeBlock
@end

IMP imp = imp_implementationWithBlock(^(id obj, NSString *str) {
     NSLog(@"%@", str);
});
class_addMethod(MyRuntimeBlock.class, @selector(testBlock:), imp, "v@:@");
MyRuntimeBlock *runtime = [[MyRuntimeBlock alloc] init];
[runtime performSelector:@selector(testBlock:) withObject:@"hello world!"];

//结果
14:03:19.779 [1172:395446] hello world!
```

# 七、Runtime的应用

## 7.1 获取系统提供的库相关信息

主要函数

```c++
// 获取所有加载的objective-c框架和动态库的名称
const char **objc_copyImageNames(unsigned int *outCount);

// 获取指定类所在动态库
const char *class_getImageName(Class cls);

// 获取指定库或框架中所有类的类名
const char **objc_copyClassNamesForImage(const char *image, unsigned int *outCount);
```

示例：通过这些函数获取某个类所在的库，以及某个库中包含哪些类：

```c++
NSLog(@"获取指定类所在动态库");

NSLog(@"UIView's Framework: %s", class_getImageName(NSClassFromString(@"UIView")));

NSLog(@"获取指定库或框架中所有类的类名");
const char ** classes = objc_copyClassNamesForImage(class_getImageName(NSClassFromString(@"UIView")), &outCount);
for (int i = 0; i < outCount; i++) {
     NSLog(@"class name: %s", classes[i]);
}

//结果
12:57:32.689 [7:1] 获取指定类所在动态库
12:57:32.690 [7:1] UIView's Framework: /System/Library/Frameworks/UIKit.framework/UIKit
12:57:32.690 [7:1] 获取指定库或框架中所有类的类名
12:57:32.691 [7:1] class name: UIKeyboardPredictiveSettings
12:57:32.691 [7:1] class name: _UIPickerViewTopFrame
12:57:32.691 [7:1] class name: _UIOnePartImageView
12:57:32.692 [7:1] class name: _UIPickerViewSelectionBar
12:57:32.692 [7:1] class name: _UIPickerWheelView
12:57:32.692 [7:1] class name: _UIPickerViewTestParameters
```

## 7.2 对App的用户行为进行追踪

就是用户点击时把事件记录下来。一般比较做法就是在viewDidAppear里记录事件，这样会让这样记录事件的代码遍布整个项目中。继承或类别也会有问题。这时利用Method Swizzling把一个方法的实现和另一个方法的实现进行替换。

```objc
//先定义一个类别，添加要Swizzled的方法
@implementation UIViewController (Logging)
- (void)swizzled_viewDidAppear:(BOOL)animated
{ // call original implementation
     [self swizzled_viewDidAppear:animated]; // Logging
     [Logging logWithEventName:NSStringFromClass([self class])];
}

//接下来实现swizzle方法
void swizzleMethod(Class class, SEL originalSelector, SEL swizzledSelector) { // the method might not exist in the class, but in its superclass
     Method originalMethod = class_getInstanceMethod(class, originalSelector);
     Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector); // class_addMethod will fail if original method already exists
     BOOL didAddMethod = class_addMethod(class, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod)); // the method doesn’t exist and we just added one
     if (didAddMethod) {
          class_replaceMethod(class, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
     }
     else {
          method_exchangeImplementations(originalMethod, swizzledMethod);
     }
}

//最后要确保在程序启动的时候调用swizzleMethod方法在之前的UIViewController的Logging类别里添加+load:方法，然后在+load:里把viewDidAppear替换掉
+ (void)load
{
     swizzleMethod([self class], @selector(viewDidAppear:), @selector(swizzled_viewDidAppear:));
}
```

更简化直接用新的IMP取代原IMP，不是替换，只需要有全局的函数指针指向原IMP即可。

```c++
void (gOriginalViewDidAppear)(id, SEL, BOOL);

void newViewDidAppear(UIViewController *self, SEL _cmd, BOOL animated)
{ // call original implementation
     gOriginalViewDidAppear(self, _cmd, animated); // Logging
     [Logging logWithEventName:NSStringFromClass([self class])];
}

+ (void)load
{
     Method originalMethod = class_getInstanceMethod(self, @selector(viewDidAppear:));
     gOriginalViewDidAppear = (void *)method_getImplementation(originalMethod);
     if(!class_addMethod(self, @selector(viewDidAppear:), (IMP) newViewDidAppear, method_getTypeEncoding(originalMethod))) {
          method_setImplementation(originalMethod, (IMP) newViewDidAppear);
     }
}
```

通过Method Swizzling可以把事件代码或Logging，Authentication，Caching等跟主要业务逻辑代码解耦。这种处理方式叫做[Cross Cutting Concerns](http://en.wikipedia.org/wiki/Cross-cutting_concern)。

用Method Swizzling动态给指定的方法添加代码解决Cross Cutting Concerns的编程方式叫[Aspect Oriented Programming](http://en.wikipedia.org/wiki/Aspect-oriented_programming)。

目前有些第三方库可以很方便的使用AOP，比如[Aspects](https://github.com/steipete/Aspects)。这里是使用[Aspects的范例](https://github.com/okcomp/AspectsDemo)。