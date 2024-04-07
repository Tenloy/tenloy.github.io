---
title: Objective-C — 深入浅出GCD常用API
date: 2020-09-11 09:12:21
urlname: GCD.html
algolia: false
tags:
  - GCD
categories:
  - iOS
---

# 一、什么是多线程编程？

先来复习一下**操作系统**中线程相关的知识点：

## 1.1 代码的运行

**首先，代码是怎么运行的？**

- 源代码通过编译器转换为CPU命令列(二进制编码)，应用程序就是CPU命令列和数据的汇集，在应用程序启动后，首先便将包含在应用程序中的CPU命令列配置在内存中。
- CPU从应用程序指定的地址开始，一个一个的执行CUP命令列。在OC的if语句和for语句等控制语句或函数调用的情况下，执行命令列的地址会远离当前的位置（位置迁移），但是由于一个CUP一次只能执行一个命令，不能执行某处分开的并列的两个命令，因此通过CPU执行的CPU命令列就好比一条无分叉的大道，其执行不会出现分歧。

**一个CPU执行的CPU命令列尾一条无分叉的路径即为“线程”**。

## 1.2 几对概念

### 1.2.1 并发和并行

- 并发：**同一时间段**有几个程序都处于已经启动到运行完毕之间，并且这几个程序都在同一个处理机上运行。
  - 并发的两种关系是同步和互斥。（互斥：进程之间访问临界资源时相互排斥的现象）
- 并行：
  - 单处理器中，进程被交替执行，表现出一种并发的外部特征；
  - 多处理器中，进程可以交替执行，还能重叠执行，实现并行处理。
- 区别：
  - 并行是指同一时刻同时做多件事情，例如，在多核处理器上，并发是两个任务可以在重叠的时间段内启动，运行和完成。
  - 并发是指同一时间间隔内做多件事情。

**并行是并发，但并发不一定是并行。**比如：我们说资源请求并发数达到了1万。这里的意思是有1万个请求同时过来了。但是这里很明显不可能真正的同时去处理这1万个请求的吧！如果这台机器的处理器有4个核心，不考虑超线程，那么我们认为同时会有4个线程在跑。

也就是说，并发访问数是1万，而底层真实的并行处理的请求数是4。如果并发数小一些只有4的话，又或者你的机器牛逼有1万个核心，那并发在这里和并行一个效果。也就是说，并发可以是虚拟的同时执行，也可以是真的同时执行。而并行的意思是真的同时执行。

**并行执行的处理数量取决于当前系统的状态**，即iOS和 OS X基于Dispatch Queue中的处理数、CPU核数以及CPU负荷等当前系统的状态来决定并行队列中并行执行的处理数。

### 1.2.2 同步和异步

- 同步：进程之间存在依赖关系，一个进程结束的输出作为另一个进程的输入。具有同步关系的一组并发进程之间发送的信息称为消息或者事件。
- 异步：和同步相对，同步是顺序执行，而异步是彼此独立，在等待某个事件的过程中继续做自己的事，不要等待这一事件完成后再工作。线程是实现异步的一个方式，异步是让调用方法的主线程不需要同步等待另一个线程的完成，从而让主线程干其他事情。

更详细的可以看：[同步和异步解读及编程中的使用场景](http://localhost:4000/2021/04/20/Sync-Async.html)。

### 1.2.3 异步 ≠ 多线程

多线程：是进程中并发运行的一段代码，能够实现线程之间的切换执行。

异步：发送一个调用请求出去，不等待其结果的返回，直接去做其它的事情，等这个异步请求有结果了通知一下。

异步和多线程不是同等关系。**异步是目的，多线程只是实现异步的一个手段**。实现异步可以采用多线程技术或者交给其他进程来处理。

## 1.3 上下文切换

> OS X 和 iOS 的核心XNU内核在发生操作系统事件时（如每隔一定时间，唤起系统调用等情况）会切换执行路经。执行中路经的状态，例如CPU的寄存器的信息保存到各自路经专用的内存块中，从切换目标路经专用的内存块中，复原CPU寄存器的信息，继续执行切换路经的CPU命令列，这被称为“上下文切换”

上下文切换是并行（单处理器中进程被交替执行，表现出并发外部特征）的核心关键。

单核中的多线程是并发，其实是顺序执行的，只不过CPU高速的切换，表面看起来像是并行。

多核中的多线程，在线程数小于 < CPU核数时，是真正的并行。

**iOS和OS X的核心 — XNU内核决定应当使用的线程数，并只生成所需的线程执行处理，另外，当处理结束，应当执行的处理数减少时，XNU内核会结束不再需要的线程，XNU内核仅使用并行队列便可完美的管理并行执行处理的线程**。

## 1.4 多线程编程的优缺点

- **优点：**保证应用程序的响应性能
- **缺点**：是易发生各种问题，比如：数据竞争、死锁，而且使用太多线程会消耗大量内存，引起大量的上下文切换，大幅度降低系统的响应性能。

## 1.5 主线程

应用程序启动时。通过最先执行的线程，即**主线程**来描绘用户界面、处理触摸屏幕的事件，如果在该线程中进行长时间的处理，会造成主线程阻塞，会妨碍主线程中被称为RunLoop的主循环执行，从而导致不能更新用户界面、应用程序画面长时间停滞等问题。

**GCD大大简化了偏于复杂的多线程编程的源代码，与Block结合使用，只需要将要执行的任务并追加到适当的Dispatch Queue**。

# 二、GCD的概述及基础知识

Grand Central Dispatch(GCD)

- 是Apple推出的一套多线程解决方案，它拥有系统级的线程管理机制，开发者不需要再管理线程的生命周期，只需要关注于要执行的任务即可。
- 是异步执行任务的技术之一，用非常简洁的技术方法，实现了极为复杂繁琐的多线程编程。

**GCD 是在系统级即iOS和OS X的核心XNU内核级上实现，所以开发者无论如何努力编写线程关系代码，`性能`都不可能胜过XNU内核级所实现的GCD。**开发者应该尽量多使用GCD或者使用了Cocoa框架GCD的NSOperationQueue类等API。

GCD的源码libdispatch版本很多，源代码风格各版本都有不同，但大体逻辑没有太大变化。libdispatch的源码下载地址[在这里](https://opensource.apple.com/tarballs/libdispatch/)。

阅读GCD的源码之前，先了解一些相关知识，方便后面的理解。

## 2.1 DISPATCH_DECL

```c++
#define DISPATCH_DECL(name) typedef struct name##_s *name##_t
```

GCD中的变量大多使用了这个宏，比如`DISPATCH_DECL(dispatch_queue)`展开后是

```c++
typedef struct dispatch_queue_s *dispatch_queue_t；
```

它的意思是定义一个`dispatch_queue_t`类型的指针，指向了一个`dispatch_queue_s`类型的结构体。

## 2.2 fastpath vs slowpath

```c++
#define fastpath(x) ((typeof(x))__builtin_expect((long)(x), ~0l))
#define slowpath(x) ((typeof(x))__builtin_expect((long)(x), 0l))
```

`__builtin_expect`是编译器用来优化执行速度的函数，fastpath表示条件更可能成立，slowpath表示条件更不可能成立。我们在阅读源码的时候可以做忽略处理。

## 2.3 TSD

Thread Specific Data(TSD)是指线程私有数据。在多线程中，会用全局变量来实现多个函数间的数据共享，局部变量来实现内部的单独访问。TSD则是能够在同一个线程的不同函数中被访问，在不同线程时，相同的键值获取的数据随线程不同而不同。可以通过pthread的相关api来实现TSD:

```c++
//创建key
int pthread_key_create(pthread_key_t *, void (* _Nullable)(void *));
//get方法
void* _Nullable pthread_getspecific(pthread_key_t);
//set方法
int pthread_setspecific(pthread_key_t , const void * _Nullable);
```

# 三、GCD的常用数据结构

## 3.1 dispatch_object_s结构体

dispatch_object_s是GCD最基础的结构体，定义如下：

```c++
//GCD的基础结构体
struct dispatch_object_s {
    DISPATCH_STRUCT_HEADER(object);
};

//os object头部宏定义
#define _OS_OBJECT_HEADER(isa, ref_cnt, xref_cnt) \
        isa; /* must be pointer-sized */ \  //isa
        int volatile ref_cnt; \             //引用计数
        int volatile xref_cnt               //外部引用计数，两者都为0时释放

//dispatch结构体头部
#define DISPATCH_STRUCT_HEADER(x) \
    _OS_OBJECT_HEADER( \
    const struct dispatch_##x##_vtable_s *do_vtable, \  //vtable结构体
    do_ref_cnt, \
    do_xref_cnt); \                            
    struct dispatch_##x##_s *volatile do_next; \   //下一个do
    struct dispatch_queue_s *do_targetq; \         //目标队列
    void *do_ctxt; \                               //上下文
    void *do_finalizer; \                          //销毁时调用函数
    unsigned int do_suspend_cnt;                   //suspend计数，用作暂停标志
```

## 3.2 dispatch_continuation_s结构体

dispatch_continuation_s结构体主要封装block和function，`dispatch_async`中的block最终都会封装成这个数据类型，定义如下：

```c++
struct dispatch_continuation_s {
    DISPATCH_CONTINUATION_HEADER(continuation);
};

//continuation结构体头部
#define DISPATCH_CONTINUATION_HEADER(x) \
    _OS_OBJECT_HEADER( \
    const void *do_vtable, \                            do_ref_cnt, \
    do_xref_cnt); \                                 //_OS_OBJECT_HEADER定义
    struct dispatch_##x##_s *volatile do_next; \    //下一个任务
    dispatch_function_t dc_func; \                  //执行内容
    void *dc_ctxt; \                                //上下文
    void *dc_data; \                                //相关数据
    void *dc_other;                                 //其他
```

## 3.3 dispatch_object_t联合体

dispatch_object_t是个union的联合体，可以用dispatch_object_t代表这个联合体里的所有数据结构。

```c++
typedef union {
    struct _os_object_s *_os_obj;
    struct dispatch_object_s *_do;             //object结构体
    struct dispatch_continuation_s *_dc;       //任务,dispatch_aync的block会封装成这个数据结构
    struct dispatch_queue_s *_dq;              //队列
    struct dispatch_queue_attr_s *_dqa;        //队列属性
    struct dispatch_group_s *_dg;              //群组操作
    struct dispatch_source_s *_ds;             //source结构体
    struct dispatch_mach_s *_dm;
    struct dispatch_mach_msg_s *_dmsg;
    struct dispatch_timer_aggregate_s *_dta;
    struct dispatch_source_attr_s *_dsa;       //source属性
    struct dispatch_semaphore_s *_dsema;       //信号量
    struct dispatch_data_s *_ddata;
    struct dispatch_io_s *_dchannel;
    struct dispatch_operation_s *_doperation;
    struct dispatch_disk_s *_ddisk;
} dispatch_object_t __attribute__((__transparent_union__));
```

## 3.4 DISPATCH_VTABLE_HEADER宏

GCD中常见结构体（比如queue、semaphore等）的vtable字段中定义了很多函数回调，在后续代码分析中会经常看到，定义如下所示：

```c++
//dispatch vtable的头部
#define DISPATCH_VTABLE_HEADER(x) \
    unsigned long const do_type; \     //类型
    const char *const do_kind; \       //种类，比如:group/queue/semaphore
    size_t (*const do_debug)(struct dispatch_##x##_s *, char *, size_t); \ //debug用
    void (*const do_invoke)(struct dispatch_##x##_s *); \    //invoke回调
    unsigned long (*const do_probe)(struct dispatch_##x##_s *); \   //probe回调
    void (*const do_dispose)(struct dispatch_##x##_s *);     //dispose回调，销毁时调用

//dx_xxx开头的宏定义，后续文章会用到，本质是调用vtable的do_xxx
#define dx_type(x) (x)->do_vtable->do_type
#define dx_metatype(x) ((x)->do_vtable->do_type & _DISPATCH_META_TYPE_MASK)
#define dx_kind(x) (x)->do_vtable->do_kind
#define dx_debug(x, y, z) (x)->do_vtable->do_debug((x), (y), (z))
#define dx_dispose(x) (x)->do_vtable->do_dispose(x)
#define dx_invoke(x) (x)->do_vtable->do_invoke(x)
#define dx_probe(x) (x)->do_vtable->do_probe(x)
```

## 3.5 dispatch_queue_s(队列结构)

dispatch_queue_s是队列的结构体，也是GCD中开发者接触最多的结构体了，定义如下：

```c++
struct dispatch_queue_s {
    DISPATCH_STRUCT_HEADER(queue);    //基础header
    DISPATCH_QUEUE_HEADER;            //队列头部，见下面的定义
    DISPATCH_QUEUE_CACHELINE_PADDING; // for static queues only
};
//队列自己的头部定义
#define DISPATCH_QUEUE_HEADER \
    uint32_t volatile dq_running; \                       //队列运行的任务数量
    struct dispatch_object_s *volatile dq_items_head; \   //链表头部节点
    struct dispatch_object_s *volatile dq_items_tail; \   //链表尾部节点
    dispatch_queue_t dq_specific_q; \                     //specific队列
    uint32_t dq_width; \                                  //队列并发数
    unsigned int dq_is_thread_bound:1; \                  //是否线程绑定
    unsigned long dq_serialnum; \                         //队列的序列号
    const char *dq_label; \                               //队列名
    DISPATCH_INTROSPECTION_QUEUE_LIST;
```

队列的do_table中有很多函数指针，阅读queue的源码时会遇到dx_invoke或者dx_probe等函数，它们其实就是调用vtable中定义的函数。下面看一下相关定义：

```c++
//main-queue和普通queue的vtable定义
DISPATCH_VTABLE_INSTANCE(queue,
    .do_type = DISPATCH_QUEUE_TYPE,
    .do_kind = "queue",
    .do_dispose = _dispatch_queue_dispose,    //销毁时调用
    .do_invoke = _dispatch_queue_invoke,      //invoke函数
    .do_probe = _dispatch_queue_probe,        //probe函数
    .do_debug = dispatch_queue_debug,         //debug回调
);
//global-queue的vtable定义
DISPATCH_VTABLE_SUBCLASS_INSTANCE(queue_root, queue,
    .do_type = DISPATCH_QUEUE_ROOT_TYPE,
    .do_kind = "global-queue",
    .do_dispose = _dispatch_pthread_root_queue_dispose,  //global-queue销毁时调用
    .do_probe = _dispatch_root_queue_probe,              //_dispatch_wakeup时会调用
    .do_debug = dispatch_queue_debug,                    //debug回调
);
```

# 四、GCD的API

## 4.1 Dispatch Queue(调度队列)

### 4.1.1 概述

`dispatch_queue`可以说是GCD编程中使用频率最高的API，这一节主要讲一下queue的相关用法和原理，关于queue的数据结构和常用定义见上节。

- Dispatch Queue按照追加的顺序（先进先出FIFO）执行处理
- Dispatch Queue分两种：
  - 一种是等待现在执行中处理结束的 Serial Dispatch Queue(串行调度队列)
  - 一种是不等待现在执行中处理结束的 Concurrent Dispatch Queue(并行调度队列)
- Dispatch Queue实例：
  - 库内置了两个队列：
    - Main Dispatch Queue(串行队列)：追加到Main Dispatch Queue中的处理在主线程的RunLoop中执行
    - Global Dispatch Queue(并行队列)
    - 对这两种队列执行 dispatch_retain 函数和 dispatch_release 函数无效，开发者无需关心这两者的保留、释放。
  - 也可以用 dispatch_queue_create 来创建串行、并行队列

### 4.1.2 使用

#### 1. dispatch_queue_create(串行与并行)

`dispatch_queue_create` 方法的文档注释：

- 提交到串行队列的block按FIFO顺序一次执行一个。上一个block执行完开始取出下一个执行。
- 提交到并发队列的block按FIFO顺序出列，但如果资源可用，则可以同时运行。
- 但是请注意，**提交到不同的、独立队列的block可以相对于彼此同时执行**。
  - 【两个block通过dispatch_async提交到一个并行队列 基本等价于 两个block通过dispatch_sync提交到两个串行队列】（都是两个线程）
  - 1个并行队列 + 多个异步任务(dispatch_async) = 会开启多线程
  - 多个【1个串行队列+1个同步/异步任务】 = 多线程


```php
/**
 * 如果您的应用程序没有使用ARC，您应该在不再需要时在调度队列上调用 dispatch_release。任何提交到队列的未执行的block都持有对该队列的引用，因此在所有未执行的block完成之前不会释放队列。
 * 
 * @参数1 指定Dispatch Queue名称（推荐使用应用程序ID这种逆序全程域名，该名称便于Xcode和Instruments调试，会出现在CrashLog中）
 * @参数2 Serial Dispatch Queue指定为NULL；Concurrent Dispatch Queue指定为DISPATCH_QUEUE_CONCURRENT
 * @return 为表示Dispatch Queue的"dispatch_queue_t类型"
 */
dispatch_queue_t mySerialDispatchQueue = dispatch_queue_create ("com.example.MySerialDispatchQueue" , NULL);

dispatch_async(queue, ^{
  
});

dispatch_release(mySerialDispatchQueue)
```

- dispatch_queue_t 类型变量，必须程序员自己负责释放，像OC的引用计数式内存管理一样，需要通过 `dispatch_retain` 函数和 `dispatch_release` 函数的引用计数来管理内存。
- 在 `dispatch_async`、`diapatch_sync` 函数中追加 Block 到 Dispatch Queue（该 Block 通过 dispatch_retain 函数持有 Dispatch Queue）。
- 一旦 Block 执行结束，就要通过 dispatch_release 函数函数释放该 Block 持有的 Dispatch Queue。


**释放时机：**

- 在 dispatch_async 函数中追加 Block 到 Dispatch Queue 后，即是立刻释放 Dispatch Queue，该 Dispatch Queue 由于被 Block 持有也不会废弃，因而 Block 能够执行，Block 执行结束后释放该 Block 持有的 Dispatch Queue，这时谁都不持有 Dispatch Queue，因此它被废弃。
- 在通过函数或方法名获取 Dispatch Queue 以及其他名称中包含 `creat` 的API生成的对象时，有必要通过 dispatch_retain 函数持有，并在不需要时通过 dispatch_release 函数释放。


系统对于一个串行队列，就只生成并使用一个线程，所以串行队列的生成个数应当仅限所必需的数量，不能大量生成。

对于并行队列，不管生成多少，由于XNU内核**只使用有效管理的线程**，不会出现串行队列那种问题。

#### 2. dispatch_async与dispatch_sync(同步与异步)

并发和串行作为队列的属性，主要影响：任务的执行方式。

- 并发：多个任务并发(同时)执行
- 串行：一个任务执行完毕后，再执行下一个任务。

同步和异步作为任务的属性，主要影响：是否阻塞当前线程下面代码的执行。 

- 同步：将block提交到队列，并执行完毕后，继续往下执行。
- 异步：将block提交到队列后，立即返回。执行下面的代码。

有的文章中说 `dispatch_sync` 与 `dispatch_async` 的区别在于会不会开辟新的线程，个人感觉是有些问题的。

- 前者的文档中只说**尽可能**在当前线程中执行。
- 后者与并行队列组合时，如果线程数已经超过64，也是不会继续创建新线程的，而是会等待线程资源的释放。
- 见下面[4.1.3-4小节]()。

当我们处理耗时操作时，比如读取数据库、请求网络数据，为了避免这些耗时操作卡住UI，可将耗时任务放到子线程中，执行完成后再通知主线程更新UI。

```c++
/**
  Submits a block for asynchronous execution on a dispatch queue and returns immediately.
  在分派队列上提交一个用于异步执行的块，然后立即返回。如果不是主队列就会开启新的线程，但不管开启不开启，都是马上返回的，不会阻塞！
*/
void dispatch_async(dispatch_queue_t queue, dispatch_block_t block);

/**
  dispatch_sync：Submits a block object for execution and returns after that block finishes executing.
  将一个block提交到指定的调度队列以同步执行。block执行完毕，dispatch_sync函数才return。
     与dispatch_async不同：
       1. 此函数在block完成之前不会返回。【阻塞在此，block执行完才能再往下走】
       2. 目标队列不执行retain。因为对该函数的调用是同步的，所以它“借用”了调用者的引用。此外，不会对block执行 Block_copy。
  */
void dispatch_sync(dispatch_queue_t queue, DISPATCH_NOESCAPE dispatch_block_t block);
```

`dispatch_sync` 函数：

- 调用此函数时，如果以当前所在的**串行队列**为目标会**【导致死锁】**！！
- 作为性能优化，此函数**【尽可能在当前线程上】**执行块。但有一个例外：提交到主调度队列的块总是在主线程上运行。

代码示例如下：

```c++
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    //耗时操作
    dispatch_async(dispatch_get_main_queue(), ^{
         //更新UI
    }); 
});
```

#### 3. GCD/NSOperation设置优先级

GCD 和 NSOperation 的优先级设置：

- NSThread 可以指定线程的优先级：iOS8之前是threadPriority，之后是qualityOfService。较高优先级不保证你的线程具体执行的时间，只是相比较低优先级的线程，它更有可能被调度器选择执⾏而已。 （*read-only after the thread is started*）
- GCD 可以指定队列优先级：（以下两者指定优先级时，使用的值不一样，有映射关系）。
  - `dispatch_queue_create` 创建队列时，指定优先级。
  - `dispatch_get_global_queue` 获取全局并行队列时，指定优先级。
- NSOperation 可以设置 operation 的 qualityOfService 属性；
- NSOperationQueue 可以设置 队列 的 qualityOfService 属性。指定了添加到该队列的 operation 对象的服务质量级别。如果 operation 显式设置过自身的 qualityOfService，则优先使用后者。


*（个人认为：队列、任务、线程的优先级可以理解为一个东西，都是在控制线程的优先级）*

通过XNU内核用于 global_queue 的线程并**不能保证实时性**，所以优先级只是个大致判断。

**XNU内核管理，会将各自使用的队列的执行优先级，作为线程的执行优先级使用，所以添加任务时，需要选择与处理的任务对应优先级的队列。**

#### 4. dispatch_set_target_queue

dispatch_queue_create函数生成的队列，生成的线程优先级为 Global Dispatch Queue 的默认优先级。

变更生成的Dispatch Queue的执行优先级要使用dispatch_set_target_queue函数

```cpp
dispatch_queue_t mySerialDispatchQueue = dispatch_queue_create("com.example.gcd.MySerialDispatchQueue",NULL);
dispatch_queue_t globalDispatchQueueBackground = dispatch_get_global_queue(DISPATCH_PRIORITY_BACKGROUND ,0);
/*
 * 指定要变更执行优先级的Dispatch Queue为dispatch_set_target_queue函数的第一个参数
 * 指定与要使用的执行优先级相同优先级的Dispatch Queue为第二个参数（目标）
 * Main Dispatch Queue和Global Dispatch Queue不可指定为第一个参数
 */
dispatch_set_target_queue(mySerialDispatchQueue, globalDispatchQueueBackground);
```

用途：

- 变更执行优先级
- 目标队列会变成第一个参数队列中任务的执行阶层
  - 多个 Serial Dispatch Queue 中用 dispatch_set_target_queue 函数指定目标为某一个 Serial Dispatch Queue，那么原先本应并行执行的多个 Serial Dispatch Queue，在目标 Serial Dispatch Queue 上只能同时执行一个处理（可防止 Serial Dispatch Queue 处理并行执行）
  - 使多个serial队列变并行为串行

### 4.1.3 实现 — Root Queue 与 线程池

#### 1. 概述

在GCD和NSOperationQueue之前，iOS使用线程一般是用NSThread，而NSThread是对[POSIX thread](http://en.wikipedia.org/wiki/POSIX_Threads)的封装，也就是pthread，本文最后会面附上一段使用pthread下图片的代码，现在我们还是继续上面的讨论。使用NSThread的一个最大的问题是：直接操纵线程，线程的生命周期完全交给developer控制，在大的工程中，模块间相互独立，假如A模块并发了8条线程，B模块需要并发6条线程，以此类推，线程数量会持续增长，最终会导致难以控制的结果。

GCD和NSOperationQueue出来以后，可以很方便地实现多线程，而不需要过多地关注线程的实现和创建等。GCD内部维护了一个线程池，由系统根据任务的数量和优先级动态地创建和分配线程执行。线程池会有效管理线程的并发，控制线程的生命周期。

developer可以不直接操纵线程，而是将所要执行的任务封装成一个unit丢给线程池去处理。

GCD是一种轻量的基于block的线程模型，使用GCD一般要注意两点：一是线程的priority，二是对象间的循环引用问题。

NSOperationQueue是对GCD更上一层的封装，它对线程的控制更好一些，但是用起来也麻烦一些。关于这两个孰优熟劣，需要根据具体应用场景进行讨论：[stackoverflow:GCD vs NSopeartionQueue](http://stackoverflow.com/questions/10373331/nsoperation-vs-grand-central-dispatch)。

下面是 objc.io上的一幅图，直观地描述GCD队列和线程的关系：

> Thread Pool 具体细节，可以看GCD的源码，开源的嘛

<img src="/images/GCD/dispatch_queue-2.png" alt="img" style="zoom:80%;" />

#### 2. GCD的16个root queue

首先，根据优先级、overcommit定义了12个：

```c++
/*
 * 从_dispatch_root_queues数组中获取对应优先级的队列。
 * _dispatch_root_queues数组中总共存放了12个root队列，优先级6种 × overcommit(过载)2种
 * 支持overcommit的队列在创建队列时无论系统是否有足够的资源都会重新开一个线程，非overcommit队列创建队列则未必创建线程。
 * 
   #define DISPATCH_QOS_MAINTENANCE        ((dispatch_qos_t)1) //优先级最低(维护线程)
   #define DISPATCH_QOS_BACKGROUND         ((dispatch_qos_t)2) //     后台
   #define DISPATCH_QOS_UTILITY            ((dispatch_qos_t)3) //     实用/多功能的
   #define DISPATCH_QOS_DEFAULT            ((dispatch_qos_t)4) //     默认
   #define DISPATCH_QOS_USER_INITIATED     ((dispatch_qos_t)5) //     用户发起
   #define DISPATCH_QOS_USER_INTERACTIVE   ((dispatch_qos_t)6) //优先级最高(用户交互)
   #define DISPATCH_QOS_MIN                DISPATCH_QOS_MAINTENANCE
   #define DISPATCH_QOS_MAX                DISPATCH_QOS_USER_INTERACTIVE
 * 
 */
typedef struct dispatch_queue_global_s *dispatch_queue_global_t;

static inline dispatch_queue_global_t _dispatch_get_root_queue(dispatch_qos_t qos, bool overcommit)
{
	if (unlikely(qos < DISPATCH_QOS_MIN || qos > DISPATCH_QOS_MAX)) {
		DISPATCH_CLIENT_CRASH(qos, "Corrupted priority");
	}
	return &_dispatch_root_queues[2 * (qos - 1) + overcommit];
}

struct dispatch_queue_global_s _dispatch_root_queues[] = {
	_DISPATCH_ROOT_QUEUE_ENTRY(MAINTENANCE, 0,
		.dq_label = "com.apple.root.maintenance-qos",
		.dq_serialnum = 4,
	),
	_DISPATCH_ROOT_QUEUE_ENTRY(MAINTENANCE, DISPATCH_PRIORITY_FLAG_OVERCOMMIT,
		.dq_label = "com.apple.root.maintenance-qos.overcommit",
		.dq_serialnum = 5,
	),
	_DISPATCH_ROOT_QUEUE_ENTRY(BACKGROUND, 0,
		.dq_label = "com.apple.root.background-qos",
		.dq_serialnum = 6,
	),
	_DISPATCH_ROOT_QUEUE_ENTRY(BACKGROUND, DISPATCH_PRIORITY_FLAG_OVERCOMMIT,
		.dq_label = "com.apple.root.background-qos.overcommit",
		.dq_serialnum = 7,
	),
	_DISPATCH_ROOT_QUEUE_ENTRY(UTILITY, 0,
		.dq_label = "com.apple.root.utility-qos",
		.dq_serialnum = 8,
	),
	_DISPATCH_ROOT_QUEUE_ENTRY(UTILITY, DISPATCH_PRIORITY_FLAG_OVERCOMMIT,
		.dq_label = "com.apple.root.utility-qos.overcommit",
		.dq_serialnum = 9,
	),
	_DISPATCH_ROOT_QUEUE_ENTRY(DEFAULT, DISPATCH_PRIORITY_FLAG_FALLBACK,
		.dq_label = "com.apple.root.default-qos",
		.dq_serialnum = 10,
	),
	_DISPATCH_ROOT_QUEUE_ENTRY(DEFAULT,
			DISPATCH_PRIORITY_FLAG_FALLBACK | DISPATCH_PRIORITY_FLAG_OVERCOMMIT,
		.dq_label = "com.apple.root.default-qos.overcommit",
		.dq_serialnum = 11,
	),
	_DISPATCH_ROOT_QUEUE_ENTRY(USER_INITIATED, 0,
		.dq_label = "com.apple.root.user-initiated-qos",
		.dq_serialnum = 12,
	),
	_DISPATCH_ROOT_QUEUE_ENTRY(USER_INITIATED, DISPATCH_PRIORITY_FLAG_OVERCOMMIT,
		.dq_label = "com.apple.root.user-initiated-qos.overcommit",
		.dq_serialnum = 13,
	),
	_DISPATCH_ROOT_QUEUE_ENTRY(USER_INTERACTIVE, 0,
		.dq_label = "com.apple.root.user-interactive-qos",
		.dq_serialnum = 14,
	),
	_DISPATCH_ROOT_QUEUE_ENTRY(USER_INTERACTIVE, DISPATCH_PRIORITY_FLAG_OVERCOMMIT,
		.dq_label = "com.apple.root.user-interactive-qos.overcommit",
		.dq_serialnum = 15,
	),
};
```

此外，还有三个特殊的队列：

```objc
struct dispatch_queue_static_s _dispatch_main_q = {
	.dq_label = "com.apple.main-thread",
	.dq_serialnum = 1,
};

struct dispatch_queue_global_s _dispatch_mgr_root_queue = {
	.dq_label = "com.apple.root.libdispatch-manager",
	.dq_serialnum = 3,
};

struct dispatch_queue_static_s _dispatch_mgr_q = {
	.dq_label = "com.apple.libdispatch-manager",
	.dq_serialnum = 2,
};
```

我们平时用到的全局队列也是其中一个root队列。见下面的`dispatch_get_global_queue` 源码。

**不管是自定义队列、全局队列还是主队列最终都直接或者间接的依赖12个root队列来执行任务调度**。如果按照label算，应该有16个：

- `_dispatch_root_queues` 数组初始化中的12个label；
- 主队列有自己的label `com.apple.main-thread`；
- 两个内部管理队列 `com.apple.libdispatch-manager` 和 `com.apple.root.libdispatch-manager`；
- runloop的运行队列。

#### 3. Queue设定的线程池的数量

`_dispatch_root_queues `取出的 `dispatch_queue_global_s` 队列的 `dgq_thread_pool_size` 字段表示queue的线程池，每个线程池的最大线程数限制是255。

```objc
#define DISPATCH_WORKQ_MAX_PTHREAD_COUNT 255
```

最大线程数设置255，但实际程序中开辟的线程数，不一定能达到这个最大值。

官方文档 [Thread Management](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/CreatingThreads/CreatingThreads.html#//apple_ref/doc/uid/10000057i-CH15-SW7) 中，辅助线程为512KB，辅助线程允许的最小堆栈大小为16KB，并且堆栈大小必须是4KB的倍数。

针对一个`4GB`内存的`iOS`真机来说，内存分为内核态和用户态。程序启动，系统给出的虚拟内存4GB，用户态占3GB，内核态占1GB。但内核态的1GB并不能全部用来开辟线程，所以最大线程数是未知的。如果内核态全部用于创建线程，也就是`1GB`的空间，也就是说最多能开辟 `1024MB / 16KB`个线程。当然这也只是一个理论值。

#### 4. 队列与线程之间的关系

再次重申：

- overcommit的队列在队列创建时会新建一个线程，非overcommit队列创建队列则未必创建线程。
- 另外，width=1意味着是串行队列，只有一个线程可用，width=0xffe则意味着并行队列，线程则是从线程池获取。

*测试现象：*

- 全局队列是非overcommit的。
- 主队列是overcommit的com.apple.root.default-qos.overcommit，不过它是串行队列，width=1，并且运行的这个线程只能是主线程。
- 自定义串行队列是overcommit的，默认优先级则是 com.apple.root.default-qos.overcommit。**创建串行队列肯定会创建1个新的线程**。
  - 最多可以创建512个，明显已经是灾难性的了，所以，**串行队列是开发中应该注意的**。【测试代码2，线程号是3-514】
- 自定义并行队列则是非overcommit的。
  - **创建并行队列不一定会新建线程，会从线程池中的64个线程中获取并使用。** 【测试代码3，线程号是3-66】
  - 如果64个线程都在使用中，那么如果再调用需要【申请新的子线程资源】的API，那么会**进行等待状态，直到有可用子线程**。【测试代码4，注意如果64个线程一直得不到释放，那么会发生死等】


```c++
/**
 测试1：使用一个串行队列，那始终只会在一个线程上执行
 **/
- (void)test2 {
    dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, -1);
    dispatch_queue_t serialQueue = dispatch_queue_create("com.cmjstudio.dispatch", attr);
    for (int i=0; i<1000; ++i) {
        dispatch_async(serialQueue, ^{
            NSLog(@"%@，%i",[NSThread currentThread],i); // 只有一个线程，线程num > 2 （3~66）
        });
    }
}

/**
 测试2：创建多个串行队列肯定会创建多个新的线程
 **/
- (void)test1 {
    for (int i=1; i<=1000; ++i) {
        dispatch_queue_t serialQueue = dispatch_queue_create("com.cmjstudio.dispatch-%d", DISPATCH_QUEUE_SERIAL);
        dispatch_async(serialQueue, ^{
            NSLog(@"%d, %@", i, [NSThread currentThread]);
            [NSThread sleepForTimeInterval:30];
        });
    }
}
// 15:30:12.822417: LOG: 3, <NSThread: 0x282ce6240>{number = 3, name = (null)}
// 15:30:12.858744: LOG: 641, <NSThread: 0x282cd85c0>{number = 514, name = (null)}

/**
 测试3：不管优先级多高并行队列有最多有64个线程，线程num在3~66，在一次轮询中遇到高优先级的会先执行
 **/
- (void)test3 {
    dispatch_queue_t concurrentQueue = dispatch_queue_create("com.cmjstudio.dispatch", DISPATCH_QUEUE_CONCURRENT);
    for (int i=0; i<1000; ++i) {
        dispatch_async(concurrentQueue, ^{
            NSLog(@"%@，%i",[NSThread currentThread],i); // 64 thread (num = 3~66)
        });
    }
}

/**
 测试4：如果64个线程都在使用中，那再次调用申请新线程的API，会进入等待。如果64个线程一直不释放，就会死等。
 **/
- (void)test4 {
    dispatch_queue_t concurrentQueue = dispatch_queue_create("com.cmjstudio.dispatch", DISPATCH_QUEUE_CONCURRENT);
    for (int i=1; i<=65; ++i) {
        dispatch_async(concurrentQueue, ^{
            NSLog(@"%d, %@", i, [NSThread currentThread]);
            [NSThread sleepForTimeInterval:3];
        });
    }
}

// 15:14:33.153114: LOG: 60, <NSThread: 0x282a733c0>{number = 62, name = (null)}
// 15:14:33.153165: LOG: 61, <NSThread: 0x282a74100>{number = 63, name = (null)}
// 15:14:33.153190: LOG: 62, <NSThread: 0x282a73780>{number = 64, name = (null)}
// 15:14:33.153266: LOG: 63, <NSThread: 0x282a75e80>{number = 65, name = (null)}
// 15:14:33.153311: LOG: 64, <NSThread: 0x282a73c00>{number = 66, name = (null)}
// 等待了3秒
// 15:14:36.154120: LOG: 65, <NSThread: 0x282a06e00>{number = 5, name = (null)}
```

GCD线程池中，线程数是64个。但有时候会超出64，[StackOverflow](https://stackoverflow.com/questions/7213845/number-of-threads-created-by-gcd)上的解释是实际线程数 = 64（最大 GCD 线程池大小）+ 主线程 + 一些其他随机非 GCD 线程。

- 参考链接：[iOS刨根问底-深入理解GCD](https://www.cnblogs.com/kenshincui/p/13272517.html)

### 4.1.4 实现 — 相关API的源码逻辑

#### 1. dispatch_get_global_queue(8种类型)

dispatch_get_global_queue用于获取一个全局队列，先看一下它的源码：

```c++
/*
 * 常见的全局队列类型有8种：下面四种优先级以及对应的是否overcommit.
 * The global concurrent queues may still be identified by their priority,
 * which map to the following QOS classes:
                                            QOS_CLASS_USER_INTERACTIVE
 *  - DISPATCH_QUEUE_PRIORITY_HIGH:         QOS_CLASS_USER_INITIATED
 *  - DISPATCH_QUEUE_PRIORITY_DEFAULT:      QOS_CLASS_DEFAULT
 *  - DISPATCH_QUEUE_PRIORITY_LOW:          QOS_CLASS_UTILITY
 *  - DISPATCH_QUEUE_PRIORITY_BACKGROUND:   QOS_CLASS_BACKGROUND
 */
dispatch_queue_global_t dispatch_get_global_queue(intptr_t priority, uintptr_t flags)
{
    dispatch_assert(countof(_dispatch_root_queues) == DISPATCH_ROOT_QUEUE_COUNT);

    if (flags & ~(unsigned long)DISPATCH_QUEUE_OVERCOMMIT) {
      return DISPATCH_BAD_INPUT;
    }
    dispatch_qos_t qos = _dispatch_qos_from_queue_priority(priority);
  #if !HAVE_PTHREAD_WORKQUEUE_QOS
    if (qos == QOS_CLASS_MAINTENANCE) {
      qos = DISPATCH_QOS_BACKGROUND;
    } else if (qos == QOS_CLASS_USER_INTERACTIVE) {
      qos = DISPATCH_QOS_USER_INITIATED;
    }
  #endif
    if (qos == DISPATCH_QOS_UNSPECIFIED) {
      return DISPATCH_BAD_INPUT;
    }
    //封装调用_dispatch_get_root_queue函数
    return _dispatch_get_root_queue(qos, flags & DISPATCH_QUEUE_OVERCOMMIT);
}
```

下面看一下global queue的do_vtable结构体，它比较重要的是do_probe的调用函数`_dispatch_root_queue_probe`，这个函数在后续的分析中会用到。结构体定义如下:

```c++
//global queue的vtable定义
DISPATCH_VTABLE_SUBCLASS_INSTANCE(queue_root, queue,
    .do_type = DISPATCH_QUEUE_ROOT_TYPE,
    .do_kind = "global-queue",
    .do_dispose = _dispatch_pthread_root_queue_dispose, //销毁时调用
    .do_probe = _dispatch_root_queue_probe,             //重要，唤醒队列时调用
    .do_debug = dispatch_queue_debug,                   //debug回调
);
```

#### 2. dispatch_get_main_queue

该API的使用主要是在更新UI时获取`dispatch_get_main_queue()`并把任务提交到主队列中。它的源码如下：

```c++
//宏定义，返回到是_dispatch_main_q
#define dispatch_get_main_queue() \
        DISPATCH_GLOBAL_OBJECT(dispatch_queue_t, _dispatch_main_q)

//main_queue结构体定义
struct dispatch_queue_s _dispatch_main_q = {
    .do_vtable = DISPATCH_VTABLE(queue),
    .do_targetq = &_dispatch_root_queues[DISPATCH_ROOT_QUEUE_IDX_DEFAULT_OVERCOMMIT_PRIORITY],  //目标队列
    .do_ref_cnt = DISPATCH_OBJECT_GLOBAL_REFCNT,   
    .do_xref_cnt = DISPATCH_OBJECT_GLOBAL_REFCNT,  
    .do_suspend_cnt = DISPATCH_OBJECT_SUSPEND_LOCK,
    .dq_label = "com.apple.main-thread",   //队列名
    .dq_running = 1,          
    .dq_width = 1,            //最大并发数是1，串行队列
    .dq_is_thread_bound = 1,  //线程绑定
    .dq_serialnum = 1,        //序列号为1
};
```

main queue设置了并发数为1，即串行队列，并且将targetq指向com.apple.root.default-overcommit-priority队列。

#### 3. dispatch_queue_create

`dispatch_queue_create`主要用来创建自定义的队列，流程图和源码如下：

<img src="/images/GCD/dispatch_queue-1.png" alt="img" style="zoom:80%;" />

```c++
/*
 * @param attr 除了预定义的DISPATCH_QUEUE_SERIAL、DISPATCH_QUEUE_CONCURRENT。也可以自定义 dispatch_queue_attr_t 变量传入。
    dispatch_queue_attr_make_initially_inactive  队列配置为最初不活动，直到调用其dispatch_activate方法时才执行任务。
    dispatch_queue_attr_make_with_autorelease_frequency 指定队列如何为其执行的blocks管理自动释放池。
    dispatch_queue_attr_make_with_qos_class 指定quality-of-service服务质量(优先级)
 * 
 * 使用示例：
 *     dispatch_queue_attr_t serialAttr = dispatch_queue_attr_make_with_qos_class(
                                              DISPATCH_QUEUE_SERIAL,       // DISPATCH_QUEUE_SERIAL(串行)或DISPATCH_QUEUE_CONCURRENT(并行)
                                              QOS_CLASS_USER_INTERACTIVE,  // 服务质量有助于确定给予队列执行的任务的优先级。(见下面的QOS类)
                                              -1);                         // 相对优先级，值为[-15,0), 同一个服务质量的队列们中，也得有个相对的优先级
 *     dispatch_queue_t userInteractiveQueue = dispatch_queue_create("com.xy.interactive.serialQueue", serialAttr);
 */
dispatch_queue_t dispatch_queue_create(const char *label, dispatch_queue_attr_t attr) {
  //调用dispatch_queue_create_with_target
    return dispatch_queue_create_with_target(label, attr, DISPATCH_TARGET_QUEUE_DEFAULT);
}

//dispatch_queue_create具体实现函数
dispatch_queue_t dispatch_queue_create_with_target(const char *label,
                                                   dispatch_queue_attr_t attr, 
                                                   dispatch_queue_t tq) {
    dispatch_queue_t dq;
   //申请内存空间
    dq = _dispatch_alloc(DISPATCH_VTABLE(queue),
                         sizeof(struct dispatch_queue_s) - DISPATCH_QUEUE_CACHELINE_PAD);
  //初始化，设置自定义队列的基本属性，方法实现见下面
    _dispatch_queue_init(dq);
    if (label) {
       //设置队列名
        dq->dq_label = strdup(label);
    }
    if (attr == DISPATCH_QUEUE_CONCURRENT) {
       //并行队列设置dq_width为UINT32_MAX
        dq->dq_width = UINT32_MAX;
        if (!tq) {
           //默认targetq，优先级为DISPATCH_QUEUE_PRIORITY_DEFAULT
            tq = _dispatch_get_root_queue(0, false);
        }
    } else {
        if (!tq) {
           //默认targetq，优先级为DISPATCH_ROOT_QUEUE_IDX_DEFAULT_OVERCOMMIT_PRIORITY
            // Default target queue is overcommit!
            tq = _dispatch_get_root_queue(0, true);
        }
    }
    //设置自定义队列的目标队列，dq队列的任务会放到目标队列执行
    dq->do_targetq = tq;
    return _dispatch_introspection_queue_create(dq);
}

//队列初始化方法
static inline void _dispatch_queue_init(dispatch_queue_t dq)
{
    dq->do_next = (struct dispatch_queue_s *)DISPATCH_OBJECT_LISTLESS;
    dq->dq_running = 0;      //队列当前运行时初始为0
    dq->dq_width = 1;        //队列并发数默认为1，串行队列
    dq->dq_serialnum = dispatch_atomic_inc_orig(&_dispatch_queue_serial_numbers, relaxed);   //序列号,在_dispatch_queue_serial_numbers基础上原子性加1
}
```

上面的代码介绍了自定义队列是如何创建的，初始化时会将dq_width默认设置为1，即串行队列。如果外部设置attr为DISPATCH_QUEUE_CONCURRENT，将并发数改为UINT32_MAX；

自定义队列的serialnum是在_dispatch_queue_serial_numbers基础上原子性加一，即从12开始累加。1到11被保留的序列号定义如下（后续版本有改动，自定义序列从16开始累加）：

```c++
// skip zero        //跳过0
// 1 - main_q       //主队列
// 2 - mgr_q        //管理队列
// 3 - mgr_root_q   //管理队列的目标队列
// 4,5,6,7,8,9,10,11 - global queues   //全局队列
// we use 'xadd' on Intel, so the initial value == next assigned
unsigned long volatile _dispatch_queue_serial_numbers = 12;
```

同时还会设置队列的target_queue，向队列提交的任务，都会被放到它的目标队列来执行。串行队列的target_queue是一个支持overcommit的root队列。

#### 4. dispatch_async

`dispatch_async`用来异步执行任务，它的代码比较复杂，我们可以分成三个阶段来看，第一阶段是更新队列链表，第二部分是从队列取任务，第三部分则是执行任务。每个阶段都有一张流程图表示，觉得代码多的话可以直接看每个阶段对应的流程图。

首先看一下`dispatch_async`的入口函数：

```c++
void dispatch_async(dispatch_queue_t dq, void (^work)(void)) {
    dispatch_async_f(dq, _dispatch_Block_copy(work), _dispatch_call_block_and_release);
}
```

dispatch_async封装调用了dispatch_async_f函数，先将block拷贝到堆上，避免block执行前被销毁，同时传入_dispatch_call_block_and_release来保证block执行后会执行Block_release。下面看一下dispatch_async_f的实现：

```c++
void dispatch_async_f(dispatch_queue_t dq, void *ctxt, dispatch_function_t func) {
    dispatch_continuation_t dc;
    if (dq->dq_width == 1) {
       //如果是串行队列，执行dispatch_barrier_async_f，和当前函数的不同点在于
       //.do_vtable = (void *)(DISPATCH_OBJ_ASYNC_BIT | DISPATCH_OBJ_BARRIER_BIT)
        return dispatch_barrier_async_f(dq, ctxt, func);
    }
    //将任务封装到dispatch_continuation_t结构体中
    dc = fastpath(_dispatch_continuation_alloc_cacheonly());
    if (!dc) {
        return _dispatch_async_f_slow(dq, ctxt, func);
    }
    dc->do_vtable = (void *)DISPATCH_OBJ_ASYNC_BIT;  //将vtable设置为ASYNC标志位
    dc->dc_func = func; 
    dc->dc_ctxt = ctxt;
    if (dq->do_targetq) {
       //如果有do_targetq，将任务放到目标队列执行
        return _dispatch_async_f2(dq, dc);
    }
    //将任务压入队列(FIFO)
    _dispatch_queue_push(dq, dc);
}
```

接下来分析一下_dispatch_queue_push，这是一个宏定义，展开后的调用栈如下:

```c++
_dispatch_queue_push
└──_dispatch_trace_queue_push
    └──_dispatch_queue_push
```

看一下_dispatch_queue_push的具体实现：

```c++
static inline void _dispatch_queue_push(dispatch_queue_t dq, dispatch_object_t _tail) {
    struct dispatch_object_s *tail = _tail._do;
    //判断链表中是否已经存在节点，有的话返回YES,否则返回NO
    if (!fastpath(_dispatch_queue_push_list2(dq, tail, tail))) {
       //将任务放到链表头部
        _dispatch_queue_push_slow(dq, tail);
    }
}
//判断链表中是否已经存在节点
static inline bool _dispatch_queue_push_list2(dispatch_queue_t dq, 
                                              struct dispatch_object_s *head,
                                              struct dispatch_object_s *tail) {
    struct dispatch_object_s *prev;
    tail->do_next = NULL;
    //将tail原子性赋值给dq->dq_items_tail，同时返回之前的值并赋给prev
    prev = dispatch_atomic_xchg2o(dq, dq_items_tail, tail, release);
    if (fastpath(prev)) {
       //如果prev不等于NULL，直接在链表尾部添加节点
        prev->do_next = head;
    }
    //链表中之前有元素返回YES，否则返回NO
    return (prev != NULL);
}
//将节点放到链表开头
void _dispatch_queue_push_slow(dispatch_queue_t dq,
                               struct dispatch_object_s *obj)
{
    if (dx_type(dq) == DISPATCH_QUEUE_ROOT_TYPE && !dq->dq_is_thread_bound) {
       //原子性的将head存储到链表头部
        dispatch_atomic_store2o(dq, dq_items_head, obj, relaxed);
        //唤醒global queue队列
        return _dispatch_queue_wakeup_global(dq);
    }
    //将obj放到链表头部并执行_dispatch_wakeup函数里的dx_probe()函数
    _dispatch_queue_push_list_slow2(dq, obj);
}
```

由上面的代码可以看出`_dispatch_queue_push`分为两种情况：

- 如果队列的链表不为空，将节点添加到链表尾部，即dq->dq_item_tail=dc。然后队列会按先进先出(FIFO)来处理任务。
- 如果队列此时为空，进入到`_dispatch_queue_push_slow`函数。
  - 如果队列是全局队列会进入if分支，原子性的将节点添加到队列开头，并执行`_dispatch_queue_wakeup_global`唤醒全局队列；
  - 如果队列是主队列或自定义串行队列if分支判断不成立，执行`_dispatch_queue_push_list_slow2`函数，它会将节点添加到队列开头并执行`_dispatch_wakeup`函数唤醒队列。

`dispatch_async`第一阶段的工作主要是封装外部任务并添加到队列的链表中，可以用下图来表示：

<img src="/images/GCD/dispatch_queue-3.png" alt="img" style="zoom:80%;" />

接着来看队列唤醒的逻辑，主要分成主队列和全局队列的唤醒和任务执行逻辑：

1、如果是主队列，会先调用`_dispatch_wakeup`唤醒队列，然后执行`_dispatch_main_queue_wakeup`函数来唤醒主线程的Runloop，代码如下：

```c++
dispatch_queue_t _dispatch_wakeup(dispatch_object_t dou) {
    if (slowpath(DISPATCH_OBJECT_SUSPENDED(dou._do))) {
        return NULL;
    }
    //_dispatch_queue_probe判断dq_items_tail是否为空，if分支不成立
    if (!dx_probe(dou._do)) {
        return NULL;
    }
    //如果dou._do->do_suspend_cnt==0，返回YES,否则返回NO；
    //同时将DISPATCH_OBJECT_SUSPEND_LOCK赋值给dou._do->do_suspend_cnt
    if (!dispatch_atomic_cmpxchg2o(dou._do, do_suspend_cnt, 0, DISPATCH_OBJECT_SUSPEND_LOCK, release)) {
            //因为主线程do_suspend_cnt非0，所以主线程if分支判断成功
#if DISPATCH_COCOA_COMPAT
        if (dou._dq == &_dispatch_main_q) {
            //主队列的任务执行和Runloop关联，唤醒主队列
            return _dispatch_main_queue_wakeup();
        }
#endif
        return NULL;
    }
    //放到目标队列中，重新走_dispatch_queue_push方法
    _dispatch_retain(dou._do);
    dispatch_queue_t tq = dou._do->do_targetq;
    _dispatch_queue_push(tq, dou._do);
    return tq;
}

//唤醒主线程Runloop
static dispatch_queue_t _dispatch_main_queue_wakeup(void) {
    dispatch_queue_t dq = &_dispatch_main_q;
    if (!dq->dq_is_thread_bound) {
        return NULL;
    }
    //只初始化一次mach_port_t
    dispatch_once_f(&_dispatch_main_q_port_pred, dq, _dispatch_runloop_queue_port_init);
    _dispatch_runloop_queue_wakeup_thread(dq);
    return NULL;
}

//唤醒runloop
static inline void _dispatch_runloop_queue_wakeup_thread(dispatch_queue_t dq) {
    mach_port_t mp = (mach_port_t)dq->do_ctxt;
    if (!mp) {
        return;
    }
    //唤醒主线程的runloop
    kern_return_t kr = _dispatch_send_wakeup_runloop_thread(mp, 0);
    switch (kr) {
    case MACH_SEND_TIMEOUT:
    case MACH_SEND_TIMED_OUT:
    case MACH_SEND_INVALID_DEST:
        break;
    default:
        (void)dispatch_assume_zero(kr);
        break;
    }
}
```

当我们调用 dispatch_async(dispatch_get_main_queue(), block) 时，libDispatch 向主线程的 RunLoop 发送消息，RunLoop会被唤醒，并从消息中取得这个 block，并在回调 __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__() 里执行这个 block。用Xcode在block处打断点就会看到下图中的调用栈:

<img src="/images/GCD/dispatch_queue-4.png" alt="img" style="zoom:80%;" />

2、如果是全局队列，调用_dispatch_queue_wakeup_global函数，它封装调用了核心函数`_dispatch_queue_wakeup_global_slow`，调用栈和核心代码如下：

```c++
_dispatch_queue_wakeup_global_slow
└──_dispatch_queue_wakeup_global2
    └──_dispatch_queue_wakeup_global_slow
```

```c++
static void _dispatch_queue_wakeup_global_slow(dispatch_queue_t dq, unsigned int n) {
    static dispatch_once_t pred;
    dispatch_root_queue_context_t qc = dq->do_ctxt;
    uint32_t i = n;
    int r;

    _dispatch_debug_root_queue(dq, __func__);
    //初始化dispatch_root_queue_context_s
    dispatch_once_f(&pred, NULL, _dispatch_root_queues_init);

#if DISPATCH_USE_PTHREAD_POOL
    //为了防止有些timer每隔一分钟调用，线程执行任务后会有65s的超时用来等待signal唤醒
    //降低线程频繁创建销毁的性能消耗
    if (fastpath(qc->dgq_thread_mediator)) {
        while (dispatch_semaphore_signal(qc->dgq_thread_mediator)) {
            if (!--i) {
                return;
            }
        }
    }
    //检测线程池可用大小，如果还有，则将线程池减一
    uint32_t j, t_count = qc->dgq_thread_pool_size;
    do {
        if (!t_count) {
          //线程池已达到最大使用量
            _dispatch_root_queue_debug("pthread pool is full for root queue: "
                    "%p", dq);
            return;
        }
        j = i > t_count ? t_count : i;
    } while (!dispatch_atomic_cmpxchgvw2o(qc, dgq_thread_pool_size, t_count, t_count - j, &t_count, relaxed));
   //创建新的线程，入口函数是_dispatch_worker_thread
    do {
        _dispatch_retain(dq);
        while ((r = pthread_create(pthr, attr, _dispatch_worker_thread, dq))) {
            if (r != EAGAIN) {
                (void)dispatch_assume_zero(r);
            }
            _dispatch_temporary_resource_shortage();
        }
        if (!attr) {
            r = pthread_detach(*pthr);
            (void)dispatch_assume_zero(r);
        }
    } while (--j);
#endif // DISPATCH_USE_PTHREAD_POOL
}
```

创建新的线程后执行`_dispatch_worker_thread`函数，代码简化后如下：

```c++
static void * _dispatch_worker_thread(void *context) {
    const int64_t timeout = (pqc ? 5ull : 65ull) * NSEC_PER_SEC;
    //为了防止有些timer每隔一分钟调用，线程执行任务后会有65s的超时用来等待signal唤醒
    //降低线程频繁创建销毁的性能消耗
    do {
       //取出一个任务并执行
        _dispatch_root_queue_drain(dq);
    } while (dispatch_semaphore_wait(qc->dgq_thread_mediator, dispatch_time(0, timeout)) == 0);
    //将线程池加一
    (void)dispatch_atomic_inc2o(qc, dgq_thread_pool_size, relaxed);
    _dispatch_queue_wakeup_global(dq);
    _dispatch_release(dq);

    return NULL;
}
```

从队列取任务的入口是_dispatch_root_queue_drain函数，简化的代码如下：

```c++
static void _dispatch_root_queue_drain(dispatch_queue_t dq) {
    _dispatch_thread_setspecific(dispatch_queue_key, dq);

#if DISPATCH_COCOA_COMPAT
    // ensure that high-level memory management techniques do not leak/crash
    if (dispatch_begin_thread_4GC) {
        dispatch_begin_thread_4GC();
    }
    //autoreleasepool的push操作
    void *pool = _dispatch_autorelease_pool_push();
#endif // DISPATCH_COCOA_COMPAT

    _dispatch_perfmon_start();
    struct dispatch_object_s *item;
    //取出队列的头部节点(FIFO)
    while ((item = fastpath(_dispatch_queue_concurrent_drain_one(dq)))) {
        //对取出的内容进行处理，核心函数
        _dispatch_continuation_pop(item);
    }
    _dispatch_perfmon_end();

#if DISPATCH_COCOA_COMPAT
    //autoreleasepool的pop操作
    _dispatch_autorelease_pool_pop(pool);
    if (dispatch_end_thread_4GC) {
        dispatch_end_thread_4GC();
    }
#endif // DISPATCH_COCOA_COMPAT

    _dispatch_thread_setspecific(dispatch_queue_key, NULL);
}
```

队列唤醒后的工作主要是用线程池(全局队列)或者唤醒Runloop(主队列)的方式从队列的链表中依次取出要执行的任务，流程图如下：

<img src="/images/GCD/dispatch_queue-5.png" alt="img" style="zoom:80%;" />

队列的任务取出之后就是核心的执行逻辑了，也就是`_dispatch_continuation_pop`函数的逻辑，代码和流程图如下所示:

```c++
static inline void _dispatch_continuation_pop(dispatch_object_t dou) {
    dispatch_continuation_t dc = dou._dc, dc1;
    dispatch_group_t dg;

    _dispatch_trace_continuation_pop(_dispatch_queue_get_current(), dou);
    //判断传入的内容是不是队列，如果是的话执行_dispatch_queue_invoke函数，否的话就是block型的
    //任务，直接执行block即可
    //dispatch_barrier_async到自定义并行队列时,dou._do是用户创建的自定义queue，此时会执行
    //_dispatch_queue_invoke，并且用信号量保证barrier的任务不会和其他任务同时执行，后续分析
    if (DISPATCH_OBJ_IS_VTABLE(dou._do)) {
        return dx_invoke(dou._do);
    }
    //判断是否带有DISPATCH_OBJ_ASYNC_BIT标志位
    if ((long)dc->do_vtable & DISPATCH_OBJ_ASYNC_BIT) {
        dc1 = _dispatch_continuation_free_cacheonly(dc);
    } else {
        dc1 = NULL;
    }
    //判断是否是group
    if ((long)dc->do_vtable & DISPATCH_OBJ_GROUP_BIT) {
        dg = dc->dc_data;
    } else {
        dg = NULL;
    }
    //dispatch_continuation_t结构体，执行dc->dc_func(dc->ctxt)
    //本质是调用Block_layout结构体的invoke执行block的实现代码
    _dispatch_client_callout(dc->dc_ctxt, dc->dc_func);
    if (dg) {
       //如果是群组执行dispatch_group_leave
        dispatch_group_leave(dg);
        _dispatch_release(dg);
    }
     _dispatch_introspection_queue_item_complete(dou);
    if (slowpath(dc1)) {
        _dispatch_continuation_free_to_cache_limit(dc1);
    }
}
```

<img src="/images/GCD/dispatch_queue-6.png" alt="img" style="zoom:80%;" />

总结一下：`dispatch_async`的流程是用链表保存所有提交的block，然后在底层线程池中，依次取出block并执行；而向主队列提交block则会向主线程的Runloop发送消息并唤醒Runloop，接着会在回调函数中取出block并执行。

#### 5. dispatch_sync

了解了dispatch_async的逻辑后，再来看下dispatch_sync的实现和流程。`dispatch_sync`主要封装调用了`dispatch_sync_f`函数，看一下具体代码:

```c++
void dispatch_sync_f(dispatch_queue_t dq, void *ctxt, dispatch_function_t func) {
    if (fastpath(dq->dq_width == 1)) {
       //串行队列执行同步方法
        return dispatch_barrier_sync_f(dq, ctxt, func);
    }
    if (slowpath(!dq->do_targetq)) {
       //global queue不要求执行顺序，直接执行具体的block
        // the global concurrent queues do not need strict ordering
        (void)dispatch_atomic_add2o(dq, dq_running, 2, relaxed);
        return _dispatch_sync_f_invoke(dq, ctxt, func);
    }
    //并发队列压入同步方法
    _dispatch_sync_f2(dq, ctxt, func);
}
```

由上面的代码可以看出，后续逻辑主要分为两种情况：

1、向串行队列提交同步任务，执行dispatch_barrier_sync_f函数：

```c++
void dispatch_barrier_sync_f(dispatch_queue_t dq, void *ctxt, dispatch_function_t func) {
    if (slowpath(dq->dq_items_tail) || slowpath(DISPATCH_OBJECT_SUSPENDED(dq))){
        return _dispatch_barrier_sync_f_slow(dq, ctxt, func);
    }
    if (slowpath(!dispatch_atomic_cmpxchg2o(dq, dq_running, 0, 1, acquire))) {
        return _dispatch_barrier_sync_f_slow(dq, ctxt, func);
    }
    if (slowpath(dq->do_targetq->do_targetq)) {
        return _dispatch_barrier_sync_f_recurse(dq, ctxt, func);
    }
    _dispatch_barrier_sync_f_invoke(dq, ctxt, func);
}
```

如果队列无任务执行，调用_dispatch_barrier_sync_f_invoke执行任务。`_dispatch_barrier_sync_f_invoke`代码逻辑展开后如下：

```c++
static void _dispatch_barrier_sync_f_invoke(dispatch_queue_t dq, void *ctxt, dispatch_function_t func) {
    //任务执行核心逻辑，将当前线程的dispatch_queue_key设置为dq，然后执行block，
    //执行完之后再恢复到之前的old_dq
    dispatch_queue_t old_dq = _dispatch_thread_getspecific(dispatch_queue_key);
    _dispatch_thread_setspecific(dispatch_queue_key, dq);
    _dispatch_client_callout(ctxt, func);
    _dispatch_perfmon_workitem_inc();
    _dispatch_thread_setspecific(dispatch_queue_key, old_dq);

    //如果队列中存在其他任务，用信号量的方法唤醒，然后继续执行下一个任务
    if (slowpath(dq->dq_items_tail)) {
        return _dispatch_barrier_sync_f2(dq);
    }
    if (slowpath(dispatch_atomic_dec2o(dq, dq_running, release) == 0)) {
        _dispatch_wakeup(dq);
    }
}
```

如果队列存在其他任务或者被挂起，调用`_dispatch_barrier_sync_f_slow`函数，等待该队列的任务执行完之后用信号量通知队列继续执行任务。代码如下：

```c++
static void _dispatch_barrier_sync_f_slow(dispatch_queue_t dq, void *ctxt, dispatch_function_t func) {
    _dispatch_thread_semaphore_t sema = _dispatch_get_thread_semaphore();
    struct dispatch_continuation_s dc = {
        .dc_data = dq,
        .dc_func = func,
        .dc_ctxt = ctxt,
        .dc_other = (void*)sema,
    };
    struct dispatch_continuation_s dbss = {
        .do_vtable = (void *)(DISPATCH_OBJ_BARRIER_BIT | DISPATCH_OBJ_SYNC_SLOW_BIT),
        .dc_func = _dispatch_barrier_sync_f_slow_invoke,
        .dc_ctxt = &dc,
#if DISPATCH_INTROSPECTION
        .dc_data = (void*)_dispatch_thread_self(),
#endif
    };
    //使用信号量等待其他任务执行完成
    _dispatch_queue_push(dq, &dbss);
    _dispatch_thread_semaphore_wait(sema); // acquire
    _dispatch_put_thread_semaphore(sema);
    //收到signal信号，继续执行当前任务
    if (slowpath(dq->do_targetq->do_targetq)) {
        _dispatch_function_recurse(dq, ctxt, func);
    } else {
        _dispatch_function_invoke(dq, ctxt, func);
    }
}
```

2、向并发队列提交同步任务，执行`_dispatch_sync_f2`函数。如果队列存在其他任务，或者队列被挂起，或者有正在执行的任务，则调用`_dispatch_sync_f_slow`函数，使用信号量等待，否则直接调用`_dispatch_sync_f_invoke`执行任务。代码如下：

```c++
static inline void _dispatch_sync_f2(dispatch_queue_t dq, void *ctxt, dispatch_function_t func) {
    if (slowpath(dq->dq_items_tail) || slowpath(DISPATCH_OBJECT_SUSPENDED(dq))){
        return _dispatch_sync_f_slow(dq, ctxt, func, false);
    }
    uint32_t running = dispatch_atomic_add2o(dq, dq_running, 2, relaxed);
    // re-check suspension after barrier check <rdar://problem/15242126>
    if (slowpath(running & 1) || slowpath(DISPATCH_OBJECT_SUSPENDED(dq))) {
        running = dispatch_atomic_sub2o(dq, dq_running, 2, relaxed);
        return _dispatch_sync_f_slow(dq, ctxt, func, running == 0);
    }
    if (slowpath(dq->do_targetq->do_targetq)) {
        return _dispatch_sync_f_recurse(dq, ctxt, func);
    }
    _dispatch_sync_f_invoke(dq, ctxt, func);
}
//队列存在其他任务|队列被挂起|有正在执行的任务，信号等待
static void _dispatch_sync_f_slow(dispatch_queue_t dq, void *ctxt, dispatch_function_t func, bool wakeup) {
    _dispatch_thread_semaphore_t sema = _dispatch_get_thread_semaphore();
    struct dispatch_continuation_s dss = {
        .do_vtable = (void*)DISPATCH_OBJ_SYNC_SLOW_BIT,
        .dc_func = func,
        .dc_ctxt = ctxt,
        .dc_data = (void*)_dispatch_thread_self(),
        .dc_other = (void*)sema,
    };
    _dispatch_queue_push_wakeup(dq, &dss, wakeup);
    //信号等待
    _dispatch_thread_semaphore_wait(sema);
    _dispatch_put_thread_semaphore(sema);
    //信号唤醒，执行同步任务
    if (slowpath(dq->do_targetq->do_targetq)) {
        _dispatch_function_recurse(dq, ctxt, func);
    } else {
        _dispatch_function_invoke(dq, ctxt, func);
    }
    if (slowpath(dispatch_atomic_sub2o(dq, dq_running, 2, relaxed) == 0)) {
        _dispatch_wakeup(dq);
    }
}
```

`dispatch_sync`的逻辑主要是将任务放入队列，并用线程专属信号量做等待，保证每次只会有一个block在执行。流程图如下：

<img src="/images/GCD/dispatch_queue-7.png" alt="img" style="zoom:80%;" />

### 4.1.5 Dispatch Quene机制的底层实现

#### 1. Dispatch Quene实现所需

GCD的Dispatch Queue非常方便，其实现会使用下面这些工具，但不仅仅只有这些：

- 用于管理追加的Block的C语言实现的FIFO队列；
- Atomic函数中实现的用于排他控制的轻量级信号；
- 用于管理线程的C语言实现的一些容器。

用于实现Dispatch Queue的几个软件组件框架：

- 组件libdispatch提供Dispatch Quene技术；
- 组件Libc(pthreads)提供pthread_workquene技术；
- 组件XNU内核提供workquene技术。

#### 2. 执行上下文

Dispatch Quene通过结构体和链表，被实现为FIFO队列。

Block并不是直接加入FIFO队列，而是先加入 `Dispatch Continuation` 这一 `dispatch_continuation_t类型` 结构体中，然后再加入 FIFO 队列。该 Dispatch Continuation 用于记忆 Block 所属的 Dispatch Group 和其他一些信息，相当于一般常说的**执行上下文**。

上面在讲 `Global Dispatch Queue` 的时候，我们介绍过8种类型，这8种 Global Dispatch Quene 各使用一个pthread_workquene。GCD初始化时，使用 `pthread_workquene_creat_np` 函数生成 pthread_workquene。

pthread_workquene包含在Libc提供的pthreads API 中。其使用bsdthread_register和workq_open系统调用，**在初始化XNU内核的workquene之后获取workquene信息**。

XNU内核持有4种workquene：

- WORKQUENE_HIGH_PRIOQUENE
- WORKQUENE_Default_PRIOQUENE
- WORKQUENE_Low_PRIOQUENE
- WORKQUENE_BG_PRIOQUENE

以上4种执行优先级的workqueue，其执行优先级与Global Dispatch Quene的四种执行优先级相同。

**Global Dispatch Queue → Libc pthread_wordqueue → XNU workqueue**

<img src="/images/GCD/gcd-imp-1.jpg" style="zoom:80%">

#### 3. Dispatch Queue执行Block的过程

1. 在Global Dispatch Queue 中执行Block时，libdispatch 从Global Dispatch Queue自身的FIFO队列取出`Dispatch Continuation`
2. 调用`pthread_workqueue_additem_np`函数将该Global Dispatch Queue 本身、符合其优先级的workqueue信息以及执行Dispatch Continuation的回调函数等传递给参数。
3. pthread_workqueue_additem_np函数使用`workq_kernreturn系统调用`，通知workqueue增加应当执行的项目。
   1. 根据该通知，XNU内核基于系统状态判断是否要生成线程。如果是`Overcommit优先级`的Global Dispatch Queue ，workqueue则始终生成线程(该线程虽然与iOS和OS X中通常使用的线程大致相同，但是有一部分pthread API不能使用)。
   2. 因为workqueue生成的线程在实现用于workqueue的线程计划表中运行，他的`上下文切换(shift context)`与普通的线程有很大的不同。这也是隐藏着使用GCD的原因。
4. workqueue的线程 --> 执行pthread_workqueue函数 --> 该函数调用libdispatch的回调函数。在该回调函数中执行加入到Global Dispatch Queue中的下一个Block。
5. Block执行结束后，进行通知Dispatch Group结束、释放Dispatch Continuation等处理，开始准备执行加入到Global Dispatch Queue中的下一个Block。

### 4.1.6 总结

dispatch_async将任务添加到队列的链表中并唤醒队列，全局队列唤醒时中会从线程池里取出可用线程，如果没有则会新建线程，然后在线程中执行队列取出的任务;主队列会唤醒主线程的Runloop，然后在Runloop循环中通知GCD执行主队列提交的任务。

dispatch_sync一般都在当前线程执行,如果是主队列的任务还是会切换到主线程执行。它使用线程信号量来实现串行执行的功能。

## 4.2 Dispatch Semaphore

### 4.2.1 API介绍

Dispatch Semaphore是持有计数的信号，该信号是多线程编程中的计数类型信号。所谓信号，类似过马路时常用的手旗，可以通过时举起手旗，不可以通过时放下手旗。

在Dispatch Semaphore中，使用计数来实现该功能：**计数为0时等待，计数为1或大于1时，减去1而不等待**。

信号量的使用比较简单，主要就三个API：`create`、`wait`和`signal`。

```cpp
/* 
 * 使用dispatch_semaphore_create函数生成Dispatch Semaphore
 * 参数value是信号量计数的初始值
 * 函数名称中包含create，必须自己通过dispatch_release函数释放，和dispatch_retain函数持有
 */
dispatch_semaphore_t dispatch_semaphore_create(intptr_t value);

/*
 * 当Dispatch Semaphore的计数值大于等于1，或者待机中计数值大于等于1时，对该计数进行减法并从dispatch_semaphore_wait函数返回。
 * 当Dispatch Semaphore的计数值为0时会等待(直到超时)
 *
 * @param timeout：等待时间 dispatch_time_t类型。DISPATCH_TIME_FOREVER
 * @return 返回值与dispatch_group_wait函数相同，0表示执行完；超时时返回非0。
 */
intptr_t dispatch_semaphore_wait(dispatch_semaphore_t dsema, dispatch_time_t timeout);

// 让信号量值加一，如果有通过dispatch_semaphore_wait函数等待Dispatch Semaphore的计数值增加的线程，会由系统唤醒最先等待的线程执行。
intptr_t dispatch_semaphore_signal(dispatch_semaphore_t dsema);

// 释放 
dispatch_release(semaphore);
```

### 4.2.2 原理

#### 1.dispatch_semaphore_t

首先看一下`dispatch_semaphore_s`的结构体定义：

```c
struct dispatch_semaphore_s {
    DISPATCH_STRUCT_HEADER(semaphore);
    semaphore_t dsema_port;    //等同于mach_port_t信号
    long dsema_orig;           //初始化的信号量值
    long volatile dsema_value; //当前信号量值
    union {
        long volatile dsema_sent_ksignals;
        long volatile dsema_group_waiters;
    };
    struct dispatch_continuation_s *volatile dsema_notify_head; //notify的链表头部
    struct dispatch_continuation_s *volatile dsema_notify_tail; //notify的链表尾部
};
```

#### 2. dispatch_semaphore_create

`dispatch_semaphore_create`用来创建信号量，创建时需要指定value，内部会将value的值存储到dsema_value(当前的value)和dsema_orig(初始value)中，value的值必须大于或等于0。

```c
dispatch_semaphore_t dispatch_semaphore_create(long value) {
    dispatch_semaphore_t dsema;
    if (value < 0) {
       //value值需大于或等于0
        return NULL;
    }
  //申请dispatch_semaphore_t的内存
    dsema = (dispatch_semaphore_t)_dispatch_alloc(DISPATCH_VTABLE(semaphore),
                                                  sizeof(struct dispatch_semaphore_s) - sizeof(dsema->dsema_notify_head) - sizeof(dsema->dsema_notify_tail));
    //调用初始化函数
    _dispatch_semaphore_init(value, dsema);
    return dsema;
}
//初始化结构体信息
static void _dispatch_semaphore_init(long value, dispatch_object_t dou) {
    dispatch_semaphore_t dsema = dou._dsema;
    dsema->do_next = (dispatch_semaphore_t)DISPATCH_OBJECT_LISTLESS;
    dsema->do_targetq = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dsema->dsema_value = value; //设置信号量的当前value值
    dsema->dsema_orig = value;  //设置信号量的初始value值
}
```

**接着来看Dispatch Semaphore很容易忽略也是最容易造成App崩溃的地方，即信号量的释放。**

创建Semaphore的时候会将do_vtable指向_dispatch_semaphore_vtable，_dispatch_semaphore_vtable的结构定义了信号量销毁的时候会执行`_dispatch_semaphore_dispose`方法，相关代码实现如下

```c
//semaphore的vtable定义
DISPATCH_VTABLE_INSTANCE(semaphore,
    .do_type = DISPATCH_SEMAPHORE_TYPE,
    .do_kind = "semaphore",
    .do_dispose = _dispatch_semaphore_dispose,  //销毁时执行的回调函数
    .do_debug = _dispatch_semaphore_debug,      //debug函数
);
```

```c
//释放信号量的函数
void _dispatch_semaphore_dispose(dispatch_object_t dou) {
    dispatch_semaphore_t dsema = dou._dsema;

    if (dsema->dsema_value < dsema->dsema_orig) {
       //Warning:信号量还在使用的时候销毁会造成崩溃
        DISPATCH_CLIENT_CRASH("Semaphore/group object deallocated while in use");
    }
    kern_return_t kr;
    if (dsema->dsema_port) {
        kr = semaphore_destroy(mach_task_self(), dsema->dsema_port);
        DISPATCH_SEMAPHORE_VERIFY_KR(kr);
    }
}
```

如果销毁时信号量还在使用，那么dsema_value会小于dsema_orig，则会引起崩溃，这是一个特别需要注意的地方。这里模拟一下信号量崩溃的代码:

```c
dispatch_semaphore_t semephore = dispatch_semaphore_create(1);
dispatch_semaphore_wait(semephore, DISPATCH_TIME_FOREVER);
//重新赋值或者将semephore = nil都会造成崩溃,因为此时信号量还在使用中
semephore = dispatch_semaphore_create(0);
```

#### 3. dispatch_semaphore_wait

```c
long dispatch_semaphore_wait(dispatch_semaphore_t dsema, dispatch_time_t timeout){
    long value = dispatch_atomic_dec2o(dsema, dsema_value, acquire);
    if (fastpath(value >= 0)) {
        return 0;
    }
    return _dispatch_semaphore_wait_slow(dsema, timeout);
}
```

`dispatch_semaphore_wait`先将信号量的dsema值原子性减一，并将新值赋给value。如果value大于等于0就立即返回，否则调用`_dispatch_semaphore_wait_slow`函数，等待信号量唤醒或者timeout超时。`_dispatch_semaphore_wait_slow`函数定义如下：

```c
static long _dispatch_semaphore_wait_slow(dispatch_semaphore_t dsema, dispatch_time_t timeout) {
    long orig;
    mach_timespec_t _timeout;
    kern_return_t kr;
again:
    orig = dsema->dsema_sent_ksignals;
    while (orig) {
        if (dispatch_atomic_cmpxchgvw2o(dsema, dsema_sent_ksignals, orig, orig - 1, &orig, relaxed)) {
            return 0;
        }
    }

    _dispatch_semaphore_create_port(&dsema->dsema_port);
    switch (timeout) {
    default:
        do {
            uint64_t nsec = _dispatch_timeout(timeout);
            _timeout.tv_sec = (typeof(_timeout.tv_sec))(nsec / NSEC_PER_SEC);
            _timeout.tv_nsec = (typeof(_timeout.tv_nsec))(nsec % NSEC_PER_SEC);
            kr = slowpath(semaphore_timedwait(dsema->dsema_port, _timeout));
        } while (kr == KERN_ABORTED);

        if (kr != KERN_OPERATION_TIMED_OUT) {
            DISPATCH_SEMAPHORE_VERIFY_KR(kr);
            break;
        }
    case DISPATCH_TIME_NOW:
        orig = dsema->dsema_value;
        while (orig < 0) {
            if (dispatch_atomic_cmpxchgvw2o(dsema, dsema_value, orig, orig + 1, &orig, relaxed)) {
                return KERN_OPERATION_TIMED_OUT;
            }
        }
    case DISPATCH_TIME_FOREVER:
        do {
            kr = semaphore_wait(dsema->dsema_port);
        } while (kr == KERN_ABORTED);
        DISPATCH_SEMAPHORE_VERIFY_KR(kr);
        break;
    }
    goto again;
}
```

`_dispatch_semaphore_wait_slow`函数根据timeout的类型分成了三种情况处理：

1. DISPATCH_TIME_NOW：若`desma_value`小于0，对其加一并返回超时信号KERN_OPERATION_TIMED_OUT，原子性加一是为了抵消`dispatch_semaphore_wait`函数开始的减一操作。
2. DISPATCH_TIME_FOREVER：调用系统的`semaphore_wait`方法，直到收到`signal`调用。

```c
kr = semaphore_wait(dsema->dsema_port);
```

3. default：调用内核方法`semaphore_timedwait`计时等待，直到有信号到来或者超时了。

```c
kr = slowpath(semaphore_timedwait(dsema->dsema_port, _timeout));
```

`dispatch_semaphore_wait`的流程图可以用下图表示：

<img src="/images/GCD/dispatch-semaphore-1.png" alt="img" style="zoom:80%;" />

#### 4. dispatch_semaphore_signal

```c
long dispatch_semaphore_signal(dispatch_semaphore_t dsema) {
    long value = dispatch_atomic_inc2o(dsema, dsema_value, release);
    if (fastpath(value > 0)) {
        return 0;
    }
    if (slowpath(value == LONG_MIN)) {
       //Warning：value值有误会造成崩溃，详见下篇dispatch_group的分析
        DISPATCH_CLIENT_CRASH("Unbalanced call to dispatch_semaphore_signal()");
    }
    return _dispatch_semaphore_signal_slow(dsema);
}
```

首先将dsema_value调用原子方法加1，如果大于零就立即返回0，否则进入`_dispatch_semaphore_signal_slow`方法，该函数会调用内核的`semaphore_signal`函数唤醒在`dispatch_semaphore_wait`中等待的线程。代码如下：

```c
long _dispatch_semaphore_signal_slow(dispatch_semaphore_t dsema) {
    _dispatch_retain(dsema);
    (void)dispatch_atomic_inc2o(dsema, dsema_sent_ksignals, relaxed);
    _dispatch_semaphore_create_port(&dsema->dsema_port);
    kern_return_t kr = semaphore_signal(dsema->dsema_port);
    DISPATCH_SEMAPHORE_VERIFY_KR(kr);

    _dispatch_release(dsema);
    return 1;
}
```

`dispatch_semaphore_signal`的流程比较简单，可以用下图表示：

<img src="/images/GCD/dispatch-semaphore-2.png" alt="img" style="zoom:80%;" />

#### 5. 总结篇

Dispatch Semaphore信号量主要是`dispatch_semaphore_wait`和`dispatch_semaphore_signal`函数，`wait`会将信号量值减一，如果大于等于0就立即返回，否则等待信号量唤醒或者超时；`signal`会将信号量值加一，如果value大于0立即返回，否则唤醒某个等待中的线程。

需要注意的是信号量在销毁或重新创建的时候如果还在使用则会引起崩溃，详见上面的分析。

### 4.2.3 应用

1、信号量常用于对资源进行加锁操作，防止多线程访问修改数据出现结果不一致甚至崩溃的问题，代码示例如下:

```c
//在init等函数初始化
_lock = dispatch_semaphore_create(1); 
dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER); 
//修改Array或字典等数据的信息

dispatch_semaphore_signal(_lock);
```

2、信号量也可用于链式请求，比如用来限制请求频次：

```c
//链式请求，限制网络请求串行执行，第一个请求成功后再开始第二个请求
- (void)chainRequestCurrentConfig {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *list = @[@"1",@"2",@"3"];
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [list enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [self fetchConfigurationWithCompletion:^(NSDictionary *dict) {
                dispatch_semaphore_signal(semaphore);
            }];
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        }];
    });
}
- (void)fetchConfigurationWithCompletion:(void(^)(NSDictionary *dict))completion {
    //AFNetworking或其他网络请求库
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        //模拟网络请求
        sleep(2);
        !completion ? nil : completion(nil);
    });
}
```

## 4.3 Dispatch Group

dispatch_group可以将GCD的任务合并到一个组里来管理。可以**指定当追加到Dispatch Queue中的多个处理全部结束时，执行某种操作。**

无论是串行还是并行队列，Dispatch Group都可监视这些处理执行的结束。一旦检测到所有的处理执行结束，就可将结束的处理追加到Dispatch Queue中。

### 4.3.1 dispatch_group_create

```c
/// 创建与block相关联的新group。 因为函数名中含有create，所以在使用结束后需要过"dispatch_release"函数释放。
dispatch_group_t dispatch_group_create(void);
```

Dispatch Group的本质是一个初始value为LONG_MAX的semaphore，通过信号量来实现一组任务的管理，源码如下：

```c
dispatch_group_t dispatch_group_create(void) {
    //申请内存空间
    dispatch_group_t dg = (dispatch_group_t)_dispatch_alloc(
            DISPATCH_VTABLE(group), sizeof(struct dispatch_semaphore_s));
    //使用LONG_MAX初始化信号量结构体
    _dispatch_semaphore_init(LONG_MAX, dg);
    return dg;
}
```

**当value等于LONG_MAX时表示所有任务已完成。**

### 4.3.2 dispatch_group_enter

```c
/// 手动指示一个block已进入group
void
dispatch_group_enter(dispatch_group_t group);
```

`dispatch_group_enter` 的逻辑是将 `dispatch_group_t` 转换成 `dispatch_semaphore_t` 后将 `dsema_value` 的值减一。源码如下：

```c
void dispatch_group_enter(dispatch_group_t dg) {
    dispatch_semaphore_t dsema = (dispatch_semaphore_t)dg;
    long value = dispatch_atomic_dec2o(dsema, dsema_value, acquire);
    if (slowpath(value < 0)) {
        DISPATCH_CLIENT_CRASH(
                "Too many nested calls to dispatch_group_enter()");
    }
}
```

### 4.3.3 dispatch_group_leave

```c
/// 手动指示group中的某个block已完成
void
dispatch_group_leave(dispatch_group_t group);
```

`dispatch_group_leave` 的逻辑是将 `dispatch_group_t` 转换成 `dispatch_semaphore_t` 后将 `dsema_value` 的值加一。源码如下：

```c
void dispatch_group_leave(dispatch_group_t dg) {
    dispatch_semaphore_t dsema = (dispatch_semaphore_t)dg;
    long value = dispatch_atomic_inc2o(dsema, dsema_value, release);
    if (slowpath(value < 0)) {
        DISPATCH_CLIENT_CRASH("Unbalanced call to dispatch_group_leave()");
    }
    if (slowpath(value == LONG_MAX)) {
        (void)_dispatch_group_wake(dsema);
    }
}
```

当value等于LONG_MAX时表示所有任务已完成，调用`_dispatch_group_wake`唤醒group，因此`dispatch_group_leave`与`dispatch_group_enter`需成对出现。

- 当调用了`dispatch_group_enter`而没有调用`dispatch_group_leave`时，会造成value值不等于LONG_MAX而不会走到唤醒逻辑，`dispatch_group_notify`函数的block无法执行或者`dispatch_group_wait`收不到`semaphore_signal`信号而卡住线程。
- 当`dispatch_group_leave`比`dispatch_group_enter`多调用了一次时，dispatch_semaphore_t的value会等于LONGMAX+1（2147483647+1），即long的负数最小值 LONG_MIN(–2147483648)。因为此时value小于0，所以会出现"Unbalanced call to dispatch_group_leave()"的崩溃，这是一个特别需要注意的地方。

### 4.3.4 dispatch_group_async

```c
/// 将block提交到调度队列，并将block与给定的调度group关联。相比dispatch_async函数不同的是通过第一个参数，指定Block属于指定的Dispatch Group
void dispatch_group_async(dispatch_group_t group,
                          dispatch_queue_t queue,
                          dispatch_block_t block);
```

源码分析：

```c
void dispatch_group_async(dispatch_group_t dg, dispatch_queue_t dq,
        dispatch_block_t db) {
    //封装调用dispatch_group_async_f函数
    dispatch_group_async_f(dg, dq, _dispatch_Block_copy(db),
            _dispatch_call_block_and_release);
}
void dispatch_group_async_f(dispatch_group_t dg, dispatch_queue_t dq, void *ctxt,
        dispatch_function_t func) {
    dispatch_continuation_t dc;
    _dispatch_retain(dg);
    //先调用dispatch_group_enter操作
    dispatch_group_enter(dg);
    dc = _dispatch_continuation_alloc();
    //DISPATCH_OBJ_GROUP_BIT会在_dispatch_continuation_pop方法中用来判断是否为group，如果为group会执行dispatch_group_leave
    dc->do_vtable = (void *)(DISPATCH_OBJ_ASYNC_BIT | DISPATCH_OBJ_GROUP_BIT);
    dc->dc_func = func;
    dc->dc_ctxt = ctxt;
    dc->dc_data = dg;
    if (dq->dq_width != 1 && dq->do_targetq) {
        return _dispatch_async_f2(dq, dc);
    }
    _dispatch_queue_push(dq, dc);
}
```

`dispatch_group_async` 的原理和 `dispatch_async` 比较类似，区别点在于group操作会带上DISPATCH_OBJ_GROUP_BIT标志位。添加group任务时会先执行 `dispatch_group_enter` ，然后在任务执行时会对带有该标记的执行 `dispatch_group_leave` 操作。

`dispatch_group_async_f `与 `dispatch_async_f`代码类似，主要执行了以下操作：

1. 调用dispatch_group_enter

2. 将block和queue等信息记录到dispatch_continuation_t中，并将它加入到group的链表中。

3. _dispatch_continuation_pop执行时会判断任务是否为group，是的话执行完任务再调用dispatch_group_leave以达到信号量value的平衡。

`_dispatch_continuation_pop`简化后的代码如下：

```c
static inline void _dispatch_continuation_pop(dispatch_object_t dou) {
    dispatch_continuation_t dc = dou._dc, dc1;
    dispatch_group_t dg;
    _dispatch_trace_continuation_pop(_dispatch_queue_get_current(), dou);
    //判断是否为队列，是的话执行队列的invoke函数
    if (DISPATCH_OBJ_IS_VTABLE(dou._do)) {
        return dx_invoke(dou._do);
    } 
    //dispatch_continuation_t结构体，执行具体任务
    if ((long)dc->do_vtable & DISPATCH_OBJ_GROUP_BIT) {
        dg = dc->dc_data;
    } else {
        dg = NULL;
    }
    _dispatch_client_callout(dc->dc_ctxt, dc->dc_func);
    if (dg) {
       //这是group操作，执行leave操作对应最初的enter
        dispatch_group_leave(dg);
        _dispatch_release(dg);
    }
}
```

### 4.3.5 dispatch_group_wait

```c
/*!
 * 同步地等待，直到与一个group相关联的所有block都完成，或者直到指定的超时已经过去
 *
 * @param timeout 指定等待时间 dispatch_time_t类型的值 (DISPATCH_TIME_FOREVER 一直)
 * @returrn  如果返回值不为0，表示经过等待，任务还在执行中; 如果为0，全部执行结束。
 */
intptr_t dispatch_group_wait(dispatch_group_t group, dispatch_time_t timeout);
```

源码分析：

```c
long dispatch_group_wait(dispatch_group_t dg, dispatch_time_t timeout) {
    dispatch_semaphore_t dsema = (dispatch_semaphore_t)dg;

    if (dsema->dsema_value == LONG_MAX) {
        return 0;
    }
    if (timeout == 0) {
        return KERN_OPERATION_TIMED_OUT;
    }
    return _dispatch_group_wait_slow(dsema, timeout);
}
```

如果当前value的值为初始值，表示任务都已经完成，直接返回0，如果timeout为0的话返回超时。其余情况会调用_dispatch_group_wait_slow方法。

```c
static long _dispatch_group_wait_slow(dispatch_semaphore_t dsema, dispatch_time_t timeout) {
    long orig;
    mach_timespec_t _timeout;
    kern_return_t kr;
again:
    if (dsema->dsema_value == LONG_MAX) {
        return _dispatch_group_wake(dsema);
    }
    (void)dispatch_atomic_inc2o(dsema, dsema_group_waiters, relaxed);
    if (dsema->dsema_value == LONG_MAX) {
        return _dispatch_group_wake(dsema);
    }
    _dispatch_semaphore_create_port(&dsema->dsema_port);
    switch (timeout) {
    default:
        do {
            uint64_t nsec = _dispatch_timeout(timeout);
            _timeout.tv_sec = (typeof(_timeout.tv_sec))(nsec / NSEC_PER_SEC);
            _timeout.tv_nsec = (typeof(_timeout.tv_nsec))(nsec % NSEC_PER_SEC);
            kr = slowpath(semaphore_timedwait(dsema->dsema_port, _timeout));
        } while (kr == KERN_ABORTED);

        if (kr != KERN_OPERATION_TIMED_OUT) {
            DISPATCH_SEMAPHORE_VERIFY_KR(kr);
            break;
        }
    case DISPATCH_TIME_NOW:
        orig = dsema->dsema_group_waiters;
        while (orig) {
            if (dispatch_atomic_cmpxchgvw2o(dsema, dsema_group_waiters, orig,
                    orig - 1, &orig, relaxed)) {
                return KERN_OPERATION_TIMED_OUT;
            }
        }
    case DISPATCH_TIME_FOREVER:
        do {
            kr = semaphore_wait(dsema->dsema_port);
        } while (kr == KERN_ABORTED);
        DISPATCH_SEMAPHORE_VERIFY_KR(kr);
        break;
    }
    goto again;
 }
```

可以看到跟dispatch_semaphore的`_dispatch_semaphore_wait_slow`方法很类似，不同点在于等待完之后调用的again函数会调用`_dispatch_group_wake`唤醒当前group。

### 4.3.6 dispatch_group_notify

```c
/*!
 * 当与一个group相关联的所有block都完成时，将一个block提交到队列中。
 * 不管指定什么样的Dispatch Queue，在追加指定的Block时，之前与Dispatch Group相关联的block都已执行结束。
 *
 * @param group 要监视的Dispatch Group
 * @param queue/block 在追加到该Dispatch Group中的全部处理执行结束时，将第三个参数的Block追加到第二个参数的Dispatch Queue中
 */
void dispatch_group_notify(dispatch_group_t group,
                           dispatch_queue_t queue,
                           dispatch_block_t block);
```

源码如下：

```c
void dispatch_group_notify(dispatch_group_t dg, dispatch_queue_t dq,
        dispatch_block_t db) {

    //封装调用dispatch_group_notify_f函数
    dispatch_group_notify_f(dg, dq, _dispatch_Block_copy(db),
            _dispatch_call_block_and_release);
}

//真正的入口函数
void dispatch_group_notify_f(dispatch_group_t dg, dispatch_queue_t dq, void *ctxt,
        void (*func)(void *)) {
    dispatch_semaphore_t dsema = (dispatch_semaphore_t)dg;
    //封装结构体
    dispatch_continuation_t prev, dsn = _dispatch_continuation_alloc();
    dsn->do_vtable = (void *)DISPATCH_OBJ_ASYNC_BIT;
    dsn->dc_data = dq;
    dsn->dc_ctxt = ctxt;
    dsn->dc_func = func;
    dsn->do_next = NULL;
    _dispatch_retain(dq);
    //将结构体放到链表尾部，如果链表为空同时设置链表头部节点并唤醒group
    prev = dispatch_atomic_xchg2o(dsema, dsema_notify_tail, dsn, release);
    if (fastpath(prev)) {
        prev->do_next = dsn;
    } else {
        _dispatch_retain(dg);
        dispatch_atomic_store2o(dsema, dsema_notify_head, dsn, seq_cst);
        dispatch_atomic_barrier(seq_cst); // <rdar://problem/11750916>
        if (dispatch_atomic_load2o(dsema, dsema_value, seq_cst) == LONG_MAX) {
            _dispatch_group_wake(dsema);
        }
    }
}
```

dispatch_group_notify的具体实现在dispatch_group_notify_f函数里，逻辑就是将block和queue封装到dispatch_continuation_t里，并将它加到链表的尾部，如果链表为空同时还会设置链表的头部节点。如果dsema_value的值等于初始值，则调用_dispatch_group_wake执行唤醒逻辑。

### 4.3.7 dispatch_group_wake(内部API)

```c
static long _dispatch_group_wake(dispatch_semaphore_t dsema) {
    dispatch_continuation_t next, head, tail = NULL, dc;
    long rval;
   //将dsema的dsema_notify_head赋值为NULL，同时将之前的内容赋给head
    head = dispatch_atomic_xchg2o(dsema, dsema_notify_head, NULL, relaxed);
    if (head) {
        //将dsema的dsema_notify_tail赋值为NULL，同时将之前的内容赋给tail
        tail = dispatch_atomic_xchg2o(dsema, dsema_notify_tail, NULL, relaxed);
    }
    rval = (long)dispatch_atomic_xchg2o(dsema, dsema_group_waiters, 0, relaxed);
    if (rval) {
        // wake group waiters
        _dispatch_semaphore_create_port(&dsema->dsema_port);
        do {
            kern_return_t kr = semaphore_signal(dsema->dsema_port);
            DISPATCH_SEMAPHORE_VERIFY_KR(kr);
        } while (--rval);
    }
    if (head) {
        // async group notify blocks
        do {
            next = fastpath(head->do_next);
            if (!next && head != tail) {
                while (!(next = fastpath(head->do_next))) {
                    dispatch_hardware_pause();
                }
            }
            dispatch_queue_t dsn_queue = (dispatch_queue_t)head->dc_data;
            dc = _dispatch_continuation_free_cacheonly(head);
            //执行dispatch_group_notify的block，见dispatch_queue的分析
            dispatch_async_f(dsn_queue, head->dc_ctxt, head->dc_func);
            _dispatch_release(dsn_queue);
            if (slowpath(dc)) {
                _dispatch_continuation_free_to_cache_limit(dc);
            }
        } while ((head = next));
        _dispatch_release(dsema);
    }
    return 0;
}
```

`dispatch_group_wake`首先会循环调用`semaphore_signal`唤醒等待group的信号量，使`dispatch_group_wait`函数中等待的线程得以唤醒；然后依次获取链表中的元素并调用`dispatch_async_f`异步执行`dispatch_group_notify`函数中注册的回调，使得notify中的block得以执行。

### 4.3.8 dispatch_release

与追加 Block 到 Dispatch Queue 时同样，Block 通过 dispatch_retain 函数持有 Dispatch Group，从而使得该 Block 属于 Dispatch Group，这样如果 Block 执行结束，该 Block 就通过 dispatch_release 函数释放持有的Dispatch Group。

一旦Dispatch Group使用结束，不用考虑属于该Dispatch Group的Block，立即通过dispatch_release函数释放即可。

### 4.3.9 原理小结

dispatch_group本质是个初始值为LONG_MAX的信号量，等待group中的任务完成其实是等待value恢复初始值。
 `dispatch_group_enter ` 和 `dispatch_group_leave` 必须成对出现：

- 如果前者比后者多一次，则wait函数等待的线程不会被唤醒和注册notify的回调block不会执行；
- 如果后者比前者多一次，则会引起崩溃。

## 4.4 dispatch_barrier_async(变无序为有序)

### 4.4.1 使用

当多线程并发读写同一个资源时，为了保证资源读写的正确性，可以用Barrier Block解决该问题。

Dispatch Barrier会确保队列中先于Barrier Block提交的任务都完成后再执行它，并且执行时队列不会同步执行其它任务，等Barrier Block执行完成后再开始执行其他任务。

代码示例如下：

```c++
// 创建自定义并行队列
dispatch_queue_t queue = dispatch_queue_create("com.gcdTest.queue", DISPATCH_QUEUE_CONCURRENT);

dispatch_async(queue, ^{  	// 第一步：执行dispatch_barrier_async之前的任务
    // 读操作
    NSLog(@"work1");
});

dispatch_barrier_async(queue, ^{  // 第二步：执行dispatch_barrier_async函数添加的任务
    // barrier block,可用于写操作
    // 确保资源更新过程中不会有其他线程读取
    NSLog(@"work2");
    sleep(1);
});

dispatch_async(queue, ^{ // 第三步：队列恢复为一般的动作，追加到Concurrent Dispatch Queue的处理又开始并行执行
    // 读操作
    NSLog(@"work3");
});
```

这里有个需要注意也是官方文档上提到的一点，如果我们调用 `dispatch_barrier_async` 时将Barrier blocks提交到一个串行队列或global queue，则此函数的行为与 `dispatch_async()` 一致；

**只有将 Barrier blocks 提交到使用 DISPATCH_QUEUE_CONCURRENT 属性创建的并行queue时它才会表现的如同预期。**

### 4.4.2 原理

`dispatch_barrier_async`是开发中解决多线程读写同一个资源比较好的方案，接下来看一下它的实现。
该函数封装调用了`dispatch_barrier_async_f`，它和dispatch_async_f类似，不同点在于vtable多了DISPATCH_OBJ_BARRIER_BIT标志位。

```c++
void dispatch_barrier_async_f(dispatch_queue_t dq, void *ctxt,
        dispatch_function_t func) {
    dispatch_continuation_t dc;
    dc = fastpath(_dispatch_continuation_alloc_cacheonly());
    if (!dc) {
        return _dispatch_barrier_async_f_slow(dq, ctxt, func);
    }
    //设置do_vtable的标志位，从队列中取任务时会用到
    dc->do_vtable = (void *)(DISPATCH_OBJ_ASYNC_BIT | DISPATCH_OBJ_BARRIER_BIT);
    dc->dc_func = func;
    dc->dc_ctxt = ctxt;

    _dispatch_queue_push(dq, dc);
}
```

`dispatch_barrier_async`如果传入的是global queue，在唤醒队列时会执行`_dispatch_queue_wakeup_global`函数，故执行效果同`dispatch_async`一致，验证了使用篇中的备注内容；
`dispatch_barrier_async`传的queue为自定义队列时，`_dispatch_continuation_pop`参数是自定义的queue，然后在`_dispatch_continuation_pop`中执行自定义队列的dx_invoke函数，即`dispatch_queue_invoke`。它的调用栈是：

```c++
_dispatch_queue_invoke
└──_dispatch_queue_class_invoke
    └──dispatch_queue_invoke2
        └──_dispatch_queue_drain
```

重点看一下_dispatch_queue_drain函数，代码如下：

```c++
_dispatch_thread_semaphore_t _dispatch_queue_drain(dispatch_object_t dou) {
    dispatch_queue_t dq = dou._dq, orig_tq, old_dq;
    old_dq = _dispatch_thread_getspecific(dispatch_queue_key);
    struct dispatch_object_s *dc, *next_dc;
    _dispatch_thread_semaphore_t sema = 0;
    orig_tq = dq->do_targetq;
    _dispatch_thread_setspecific(dispatch_queue_key, dq);

    while (dq->dq_items_tail) {
        dc = _dispatch_queue_head(dq);
        do {
            if (DISPATCH_OBJECT_SUSPENDED(dq)) {
               //barrier block执行时修改了do_suspend_cnt导致此时为YES
               //保证barrier block执行时其他block不会同时执行
                goto out;
            }
            if (dq->dq_running > dq->dq_width) {
                goto out;
            }
            bool redirect = false;
            if (!fastpath(dq->dq_width == 1)) {
                if (!DISPATCH_OBJ_IS_VTABLE(dc) &&
                        (long)dc->do_vtable & DISPATCH_OBJ_BARRIER_BIT) {
                    if (dq->dq_running > 1) {
                        goto out;
                    }
                } else {
                    redirect = true;
                }
            }
            next_dc = _dispatch_queue_next(dq, dc);
            if (redirect) {
                _dispatch_continuation_redirect(dq, dc);
                continue;
            }
            //barrier block之前的block已经执行完，开始执行barrier block
            if ((sema = _dispatch_barrier_sync_f_pop(dq, dc, true))) {
                goto out;
            }
            _dispatch_continuation_pop(dc);
            _dispatch_perfmon_workitem_inc();
        } while ((dc = next_dc));
    }
out:
    _dispatch_thread_setspecific(dispatch_queue_key, old_dq);
    return sema;
}
```

在while循环中依次取出任务并调用`_dispatch_continuation_redirect`函数，使得block并发执行。当遇到DISPATCH_OBJ_BARRIER_BIT标记时，会修改do_suspend_cnt标志以保证后续while循环时直接goto out。barrier block的任务执行完之后`_dispatch_queue_class_invoke`会将do_suspend_cnt重置回去，所以barrier block之后的任务会继续执行。

`dispatch_barrier_async`的流程见下图：

<img src="/images/GCD/dispatch_queue-8.png" alt="img" style="zoom:80%;" />

## 4.5 dispatch_apply

dispatch_apply 函数是 dispatch_sync 函数和 Dispatch Group 的关联 API。该函数 **按指定的次数** 将指定的Block追加到指定的队列中，并等待全部处理执行结束。

```cpp
/*
 * 参数1：重复次数
 * 参数2：执行队列
 * 参数3：任务
 */
dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRORITY_DEFAULT,0);
dispatch_apply(10, queue, ^(size_t index){
   NSLog(@"%zu",index);
});
NSLog（@"done"）;
```

- Global Dispatch Queue中执行，所以各个处理的执行时间不定，但是输出结果的最后必定是done，这是因为dispatch_apply函数会等待全部处理执行结束。
- dispatch_apply和dispatch_sync函数一样，会等待处理执行结束，因此推荐在dispatch_async函数中非同步的执行dispatch_apply函数
```objectivec
dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRORITY_DEFAULT,0);

//在Global Dispatch Queue中非同步执行
dispatch_async(queue, ^{

  //Global Dispatch Queue,等待dispatch_apply函数中全部处理执行结束
    dispatch_apply([array count], queue, ^(size_t index){   
  
      //并列处理包含在NSArray对象的全部对象  index为0-10
       NSLog(@"%zu ：%@",index,[array objectAtIndex:index]);
    });

   //dispatch_apply函数中的处理全部执行结束
   //在Main Dispatch Queue中非同步执行
   dispatch_async(dispatch_get_main_queue(),^{
   
     //在Main Dispatch Queue中执行处理
     NSLog（@"done"）;
  });
  
});
```

## 4.6 dispatch_suspend/dispatch_resume

队列的挂起与恢复

```cpp
//dispatch_suspend函数挂起指定的Dispatch Queue
dispatch_suspend(queue)
//dispatch_suspend函数恢复指定的Dispatch Queue
dispatch_resume(queue)
```

函数**对已经执行的处理没有影响**。

- 挂起后，追加到Dispatch Queue中但尚未执行的处理，在此之后停止执行
- 恢复后使得这些处理能继续执行

## 4.7 dispatch_once

dispatch_once函数时保证在应用程序执行中只执行一次指定处理的API，即使同时多线程调用也是**线程安全**的。

常用于创建单例、swizzeld method等功能。

### 4.7.1 API介绍

```c++
static dispatch_once_t onceToken;
dispatch_once(&onceToken, ^{
    //创建单例、method swizzled或其他任务
});
```

### 4.7.2 原理

```c++
//调用dispatch_once_f来处理
void dispatch_once(dispatch_once_t *val, dispatch_block_t block) {
    dispatch_once_f(val, block, _dispatch_Block_invoke(block));
}
```

`dispatch_once`封装调用了`dispatch_once_f`函数，其中通过_dispatch_Block_invoke来执行block任务，它的定义如下：

```c++
//invoke是指触发block的具体实现，感兴趣的可以看一下Block_layout的结构体
#define _dispatch_Block_invoke(bb) \
        ((dispatch_function_t)((struct Block_layout *)bb)->invoke)
```

接着看一下具体的实现函数`dispatch_once_f`：

```c++
void dispatch_once_f(dispatch_once_t *val, void *ctxt, dispatch_function_t func) {
    struct _dispatch_once_waiter_s * volatile *vval =
            (struct _dispatch_once_waiter_s**)val;
    struct _dispatch_once_waiter_s dow = { NULL, 0 };
    struct _dispatch_once_waiter_s *tail, *tmp;
    _dispatch_thread_semaphore_t sema;

    if (dispatch_atomic_cmpxchg(vval, NULL, &dow, acquire)) {
        _dispatch_client_callout(ctxt, func);

        dispatch_atomic_maximally_synchronizing_barrier();
        // above assumed to contain release barrier
        tmp = dispatch_atomic_xchg(vval, DISPATCH_ONCE_DONE, relaxed);
        tail = &dow;
        while (tail != tmp) {
            while (!tmp->dow_next) {
                dispatch_hardware_pause();
            }
            sema = tmp->dow_sema;
            tmp = (struct _dispatch_once_waiter_s*)tmp->dow_next;
            _dispatch_thread_semaphore_signal(sema);
        }
    } else {
        dow.dow_sema = _dispatch_get_thread_semaphore();
        tmp = *vval;
        for (;;) {
            if (tmp == DISPATCH_ONCE_DONE) {
                break;
            }
            if (dispatch_atomic_cmpxchgvw(vval, tmp, &dow, &tmp, release)) {
                dow.dow_next = tmp;
                _dispatch_thread_semaphore_wait(dow.dow_sema);
                break;
            }
        }
        _dispatch_put_thread_semaphore(dow.dow_sema);
    }
}
```

由上面的代码可知`dispatch_once`的流程图大致如下：

<img src="/images/GCD/dispatch_once.png" alt="img" style="zoom:80%;" />

首先看一下`dispatch_once`中用的的原子性操作`dispatch_atomic_cmpxchg(vval, NULL, &dow, acquire)`，它的宏定义展开之后会将$dow赋值给vval，如果vval的初始值为NULL，返回YES,否则返回NO。

接着结合上面的流程图来看下`dispatch_once`的代码逻辑：

首次调用`dispatch_once`时，因为外部传入的dispatch_once_t变量值为nil，故vval会为NULL，故if判断成立。然后调用`_dispatch_client_callout`执行block，然后在block执行完成之后将vval的值更新成`DISPATCH_ONCE_DONE`表示任务已完成。最后遍历链表的节点并调用`_dispatch_thread_semaphore_signal`来唤醒等待中的信号量；

当其他线程同时也调用`dispatch_once`时，因为if判断是原子性操作，故只有一个线程进入到if分支中，其他线程会进入else分支。在else分支中会判断block是否已完成，如果已完成则跳出循环；否则就是更新链表并调用`_dispatch_thread_semaphore_wait`阻塞线程，等待if分支中的block完成后再唤醒当前等待的线程。

### 4.7.3 总结

`dispatch_once`用原子性操作block执行完成标记位，同时用信号量确保只有一个线程执行block，等block执行完再唤醒所有等待中的线程。

`dispatch_once`常被用于创建单例、swizzeld method等功能。

## 4.8 Dispatch I/O与Dispatch Data对象

通过 Dispatch I/O 读写文件，使用 Global Dispatch Queue 将一个文件按大小 read/write。提升读取、写入速度

```cpp
//创建队列
pipe_q = dispatch_queue_create("PipeQ",NULL);  

//创建Dispatch I/O对象
pipe_channel = dispatch_io_create(DISPATCH_IO_STREAM,fd,pipe_q,^(int err){
   close(fd);   //发生错误时执行
});

*out_fd = fdpair[i];

//设置一次读取的最大字节
dispatch_io_set_high_water(pipe_channel, SIZE_MIN);

//设置一次读取的最小字节
dispatch_io_set_low_water(pipe_channel, SIZE_MAX);
 
//开始异步读取
dispatch_io_read(pipe_channel,0,SIZE_MAX,pipe_q, ^(bool done,dispatch_data_t pipe data,int err){
//每当各个分割的文件快读取结束时，将含有文件块数据的Dispatch Data传递给dispatch_io_read函数指定的读取结束时回调用的Block。回调用的Block分析传递过来的Dispatch Data并进行结合处理
    if(err == 0)
    {
        size_t len = dispatch_data_get_size(pipe data);
        if(len > 0)
        {
            const char *bytes = NULL;
            char *encoded;

            dispatch_data_t md = dispatch_data_create_map(pipe data, (const void **)&bytes, &len);
            asl_set((aslmsg)merged_msg, ASL_KEY_AUX_DATA, encoded);
            free(encoded);
            _asl_send_message(NULL, merged_msg, -1, NULL);
            asl_msg_release(merged_msg);
            dispatch_release(md);
        }
    }

    if(done)
    {
       dispatch_semaphore_signal(sem);
       dispatch_release(pipe_channel);
       dispatch_release(pipe_q);
    }
});
```

## 4.9 dispatch_source

GCD中除了主要的Dispatch Queue外，还有不太引人注目的Dispatch Source。它是BSD系内核惯有功能**kqueue的包装**。

kqueue是XNU内核中发生各种事件时，在应用程序编程方执行处理的技术。其CPU负荷非常小，尽量不占用资源。kqueue可以说是应用程序处理XNU内核中发生的各种事件的方法中最优秀的一种。

Dispatch Source可处理以下事件：

```c++
DISPATCH_SOURCE_TYPE_DATA_ADD   // 变量增加
DISPATCH_SOURCE_TYPE_DATA_OR    // 变量OR
DISPATCH_SOURCE_TYPE_MACH_SEND  // MACH端口发送
DISPATCH_SOURCE_TYPE_MACH_RECV  // MACH端口接收
DISPATCH_SOURCE_TYPE_PROC       // 检测到与进程相关的事件
DISPATCH_SOURCE_TYPE_READ       // 可读取文件映像
DISPATCH_SOURCE_TYPE_SIGNAL     // 接收信号
DISPATCH_SOURCE_TYPE_TIMER      // 定时器
DISPATCH_SOURCE_TYPE_VNODE      // 文件系统有变更
DISPATCH_SOURCE_TYPE_WRITE      // 可写入文件映像
```

当事件发生时，Dispatch Source会在指定的Dispatch Queue中执行事件的处理。

```cpp
dispatch_queue_t queue = dispatc_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
/*
 *  基于READ事件作成Dispatch Source
 */  
dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, sockfd, 0 , queuq);

/* 指定发生READ事件时执行的处理 */    
dispatch_source_set_event_handler(source, ^{
    // 处理结束，取消Dispatch Source
    dispatch_source_cancel(source);
});

/* 指定取消Dispatch Source时的处理 */
dispatch_source_set_cancel_handler(source, ^{
    /* 释放Dispatch Source(自身) */
    dispatch_release(source);
});

/* 启动Dispatch Source */
dispatch_resume(source);
```

与上面代码非常相似的代码，使用在了Core Foundation框架的用于异步网络的`API CFSocket`中。因为**Foundation框架的异步网络API是通过CFSocket实现**的，所以可享受到仅使用Foundation框架的Dispatch Source(即GCD)带来的好处。

一旦将任务追加到Dispatch Queue中，就没有办法将任务取消，也没有办法在执行中取消任务。Dispatch Source是可以取消的，而且取消时的处理可以block的形式作为参数配置。**在必须使用kqueue的情况下，推荐大家使用Dispatch Source，比较简单**。

### 4.9.1 kqueue

kqueue是IO多路复用在BSD系统中的一种实现，它的接口主要包括 kqueue()、kevent() 两个系统调用和 struct kevent 结构：

```c
// kqueue() 生成一个内核事件队列，返回该队列的文件描述符。
int kqueue(void);

// kevent() 提供向内核注册/反注册事件和返回就绪事件或错误事件。
int kevent(int kq, 
         const struct kevent *changelist, int nchanges,
         struct kevent *eventlist, int nevents,
         const struct timespec *timeout);

// struct kevent 就是kevent()操作的最基本的事件结构。
struct kevent { 
     uintptr_t ident;        /* 事件 ID */ 
     short     filter;       /* 事件过滤器 */ 
     u_short   flags;        /* 行为标识 */ 
     u_int     fflags;       /* 过滤器标识值 */ 
     intptr_t  data;         /* 过滤器数据 */ 
     void      *udata;       /* 应用透传数据 */ 
};
```

在一个 kqueue 中，{ident, filter} 确定一个唯一的事件：

- ident 事件的 id，一般设置为文件描述符。
- filter 可以将 kqueue filter 看作事件。内核检测 ident 上注册的 filter 的状态，状态发生了变化，就通知应用程序。kqueue 定义了较多的 filter：

  ```c
  #define EVFILT_READ         (-1)
  #define EVFILT_WRITE        (-2)
  #define EVFILT_AIO          (-3)    /* attached to aio requests */
  #define EVFILT_VNODE        (-4)    /* attached to vnodes */
  #define EVFILT_PROC         (-5)    /* attached to struct proc */
  #define EVFILT_SIGNAL       (-6)    /* attached to struct proc */
  #define EVFILT_TIMER        (-7)    /* timers */
  #define EVFILT_MACHPORT     (-8)    /* Mach portsets */
  #define EVFILT_FS           (-9)    /* Filesystem events */
  #define EVFILT_USER         (-10)   /* User events */
  ```

- 行为标志flags：

  ```c
  #define EV_ADD              0x0001      /* add event to kq (implies enable) */
  #define EV_DELETE           0x0002      /* delete event from kq */
  #define EV_ENABLE           0x0004      /* enable event */
  #define EV_DISABLE          0x0008      /* disable event (not reported) */
  ```

### 4.9.2 使用示例：定时器

在使用定时器时，NSTimer是首先被想到的，但是由于NSTimer会受RunLoop影响，当RunLoop处理的任务很多时，就会导致NSTimer的精度降低，所以在一些对定时器精度要求很高的情况下，我们会考虑CADisplaylink，但是实际上也可以考虑使用GCD定时器。

dispatch_source最常见的用法就是用来实现定时器，代码如下：

```c
dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
dispatch_source_set_timer(source, dispatch_time(DISPATCH_TIME_NOW, 0), 3 * NSEC_PER_SEC, 0);
dispatch_source_set_event_handler(source, ^{
    //定时器触发时执行
   NSLog(@"timer响应了");
});
//启动timer
dispatch_resume(source);
```

`Dispatch Source`定时器的代码看似很简单，但其实是GCD中坑最多的API了，如果处理不好很容易引起Crash。关于`Dispatch Source`定时器需要注意的知识点请参考文章最后的总结篇。

### 4.9.3 常用API

#### 1. dispatch_source_create

`dispatch_source_create`函数用来创建dispatch_source_t对象，简化后的代码如下：

```c
dispatch_source_t dispatch_source_create(dispatch_source_type_t type,
    uintptr_t handle,
    unsigned long mask,
    dispatch_queue_t q) {
    //申请内存空间
    ds = _dispatch_alloc(DISPATCH_VTABLE(source),
            sizeof(struct dispatch_source_s));
    //初始化ds
    _dispatch_queue_init((dispatch_queue_t)ds);
    ds->dq_label = "source";

    ds->do_ref_cnt++; // the reference the manager queue holds
    ds->do_ref_cnt++; // since source is created suspended
    //默认处于暂状态，需要手动调用resume
    ds->do_suspend_cnt = DISPATCH_OBJECT_SUSPEND_INTERVAL;
    ds->do_targetq = &_dispatch_mgr_q;
    // First item on the queue sets the user-specified target queue
    //设置事件回调的队列
    dispatch_set_target_queue(ds, q);
    _dispatch_object_debug(ds, "%s", __func__);
    return ds;
}
```

#### 2. dispatch_source_set_timer

dispatch_source_set_timer实际上调用了_dispatch_source_set_timer，看一下代码：

```c++
/*
 * start计时器起始时间，可以通过dispatch_time创建，如果使用DISPATCH_TIME_NOW，则创建后立即执行
 * interval计时器间隔时间，可以通过timeInterval * NSEC_PER_SEC来设置，其中，timeInterval为对应的秒数
 * leeway这个参数的理解，我觉得网上有处解释很直观也很易懂：“这个参数告诉系统我们需要计时器触发的精准程度。所有的计时器都不会保证100%精准，这个参数用来告诉系统你希望系统保证精准的努力程度。如果你希望一个计时器没五秒触发一次，并且越准越好，那么你传递0为参数。另外，如果是一个周期性任务，比如检查email，那么你会希望每十分钟检查一次，但是不用那么精准。所以你可以传入60，告诉系统60秒的误差是可接受的。这样有什么意义呢？简单来说，就是降低资源消耗。如果系统可以让cpu休息足够长的时间，并在每次醒来的时候执行一个任务集合，而不是不断的醒来睡去以执行任务，那么系统会更高效。如果传入一个比较大的leeway给你的计时器，意味着你允许系统拖延你的计时器来将计时器任务与其他任务联合起来一起执行。
 */
static inline void _dispatch_source_set_timer(dispatch_source_t ds, 
                                              dispatch_time_t start,
                                              uint64_t interval, 
                                              uint64_t leeway, 
                                              bool source_sync) {
    //首先屏蔽非timer类型的source
    if (slowpath(!ds->ds_is_timer) ||
            slowpath(ds_timer(ds->ds_refs).flags & DISPATCH_TIMER_INTERVAL)) {
        DISPATCH_CLIENT_CRASH("Attempt to set timer on a non-timer source");
    }
    //创建dispatch_set_timer_params结构体绑定source和timer参数
    struct dispatch_set_timer_params *params;
    params = _dispatch_source_timer_params(ds, start, interval, leeway);
    _dispatch_source_timer_telemetry(ds, params->ident, &params->values);
    dispatch_retain(ds);
    if (source_sync) {
       //将source当做队列使用，执行dispatch_barrier_async_f压入队列，
       //核心函数为_dispatch_source_set_timer2
        return _dispatch_barrier_trysync_f((dispatch_queue_t)ds, params,
                _dispatch_source_set_timer2);
    } else {
        return _dispatch_source_set_timer2(params);
    }
}
```

`_dispatch_source_set_timer`实际上是调用了`_dispatch_source_set_timer2`函数:

```c++
static void _dispatch_source_set_timer2(void *context) {
    // Called on the source queue
    struct dispatch_set_timer_params *params = context;
    //暂停队列，避免修改过程中定时器被触发了。
    dispatch_suspend(params->ds);
    //在_dispatch_mgr_q队列上执行_dispatch_source_set_timer3(params)
    dispatch_barrier_async_f(&_dispatch_mgr_q, params,
            _dispatch_source_set_timer3);
}
```

`_dispatch_source_set_timer2`函数的逻辑是在_dispatch_mgr_q队列执行`_dispatch_source_set_timer3(params)`，接下来的逻辑如下：

```c++
static void _dispatch_source_set_timer3(void *context) {
    // Called on the _dispatch_mgr_q
    struct dispatch_set_timer_params *params = context;
    dispatch_source_t ds = params->ds;
    ds->ds_ident_hack = params->ident;
    ds_timer(ds->ds_refs) = params->values;
    ds->ds_pending_data = 0;
    (void)dispatch_atomic_or2o(ds, ds_atomic_flags, DSF_ARMED, release);
    //恢复队列，对应着_dispatch_source_set_timer2函数中的dispatch_suspend
    dispatch_resume(ds);
    // Must happen after resume to avoid getting disarmed due to suspension
    //根据下一次触发时间将timer进行排序
    _dispatch_timers_update(ds);
    dispatch_release(ds);
    if (params->values.flags & DISPATCH_TIMER_WALL_CLOCK) {
        _dispatch_mach_host_calendar_change_register();
    }
    free(params);
}
```

当执行提交到_dispatch_mgr_q队列的block时，会调用&_dispatch_mgr_q->do_invoke函数，即&_dispatch_mgr_q的vtable中定义的`_dispatch_mgr_thread`。接下来会走到`_dispatch_mgr_invoke`函数。在这个函数里用I/O多路复用功能的select来实现定时器功能:

```c++
r = select(FD_SETSIZE, &tmp_rfds, &tmp_wfds, NULL,
            poll ? (struct timeval*)&timeout_immediately : NULL);
```

当内层的 `_dispatch_mgr_q` 队列被唤醒后，还会进一步唤醒外层的队列(当初用户指定的那个)，并在指定队列上执行 timer 触发时的 block。

#### 3. dispatch_source_set_event_handler

```c++
void dispatch_source_set_event_handler(dispatch_source_t ds,
        dispatch_block_t handler) {
    //将block进行copy后压入到队列中
    handler = _dispatch_Block_copy(handler);
    _dispatch_barrier_trysync_f((dispatch_queue_t)ds, handler,
            _dispatch_source_set_event_handler2);
}
static void _dispatch_source_set_event_handler2(void *context) {
    dispatch_source_t ds = (dispatch_source_t)_dispatch_queue_get_current();
    dispatch_assert(dx_type(ds) == DISPATCH_SOURCE_KEVENT_TYPE);
    dispatch_source_refs_t dr = ds->ds_refs;

    if (ds->ds_handler_is_block && dr->ds_handler_ctxt) {
        Block_release(dr->ds_handler_ctxt);
    }
    //设置上下文，保存提交的block等信息
    dr->ds_handler_func = context ? _dispatch_Block_invoke(context) : NULL;
    dr->ds_handler_ctxt = context;
    ds->ds_handler_is_block = true;
}
```

#### 4. dispatch_source_set_cancel_handler

`dispatch_source_set_cancel_handler`与`dispatch_source_set_event_handler`功能类似，保存一下取消事件处理的上下文信息。代码如下：

```c++
void dispatch_source_set_cancel_handler(dispatch_source_t ds,
    dispatch_block_t handler) {
    //将block进行copy后压入到队列中
    handler = _dispatch_Block_copy(handler);
    _dispatch_barrier_trysync_f((dispatch_queue_t)ds, handler,
            _dispatch_source_set_cancel_handler2);
}

static void _dispatch_source_set_cancel_handler2(void *context) {
    dispatch_source_t ds = (dispatch_source_t)_dispatch_queue_get_current();
    dispatch_assert(dx_type(ds) == DISPATCH_SOURCE_KEVENT_TYPE);
    dispatch_source_refs_t dr = ds->ds_refs;

    if (ds->ds_cancel_is_block && dr->ds_cancel_handler) {
        Block_release(dr->ds_cancel_handler);
    }
    //保存事件取消的信息
    dr->ds_cancel_handler = context;
    ds->ds_cancel_is_block = true;
}
```

#### 5. dispatch_resume/dispatch_suspend

```c++
//恢复
void dispatch_resume(dispatch_object_t dou) {
    DISPATCH_OBJECT_TFB(_dispatch_objc_resume, dou);
    // Global objects cannot be suspended or resumed.
    if (slowpath(dou._do->do_ref_cnt == DISPATCH_OBJECT_GLOBAL_REFCNT) ||
            slowpath(dx_type(dou._do) == DISPATCH_QUEUE_ROOT_TYPE)) {
        return;
    }
    //将do_suspend_cnt原子性减二，并返回之前存储的值
    unsigned int suspend_cnt = dispatch_atomic_sub_orig2o(dou._do,
             do_suspend_cnt, DISPATCH_OBJECT_SUSPEND_INTERVAL, relaxed);
    if (fastpath(suspend_cnt > DISPATCH_OBJECT_SUSPEND_INTERVAL)) {
        return _dispatch_release(dou._do);
    }
    if (fastpath(suspend_cnt == DISPATCH_OBJECT_SUSPEND_INTERVAL)) {
        _dispatch_wakeup(dou._do);
     return _dispatch_release(dou._do);
    }
    DISPATCH_CLIENT_CRASH("Over-resume of an object");
}

//暂停
void dispatch_suspend(dispatch_object_t dou) {
    DISPATCH_OBJECT_TFB(_dispatch_objc_suspend, dou);
    if (slowpath(dou._do->do_ref_cnt == DISPATCH_OBJECT_GLOBAL_REFCNT) ||
            slowpath(dx_type(dou._do) == DISPATCH_QUEUE_ROOT_TYPE)) {
        return;
    }
    //将do_suspend_cnt原子性加二
    (void)dispatch_atomic_add2o(dou._do, do_suspend_cnt,
            DISPATCH_OBJECT_SUSPEND_INTERVAL, relaxed);
    _dispatch_retain(dou._do);
}
```

判断队列是否暂停的依据是do_suspend_cnt是否大于等于2,全局队列和主队列默认都是小于2的，即处于启动状态。
而dispatch_source_create方法中，do_suspend_cnt初始为DISPATCH_OBJECT_SUSPEND_INTERVAL，即默认处于暂停状态，需要手动调用resume开启。
代码定义如下：

```c++
#define DISPATCH_OBJECT_SUSPEND_LOCK        1u
#define DISPATCH_OBJECT_SUSPEND_INTERVAL    2u
#define DISPATCH_OBJECT_SUSPENDED(x) \
        ((x)->do_suspend_cnt >= DISPATCH_OBJECT_SUSPEND_INTERVAL)
```

### 4.9.4 总结

Dispatch Source使用最多的就是用来实现定时器，source创建后默认是暂停状态，需要手动调用`dispatch_resume`启动定时器。`dispatch_after`只是封装调用了dispatch source定时器，然后在回调函数中执行定义的block。

Dispatch Source定时器使用时也有一些需要注意的地方，不然很可能会引起crash：

1. 循环引用：因为dispatch_source_set_event_handler回调是个block，在添加到source的链表上时会执行copy并被source强引用，如果block里持有了self，self又持有了source的话，就会引起循环引用。正确的方法是使用weak+strong或者提前调用dispatch_source_cancel取消timer。
2. `dispatch_resume`和`dispatch_suspend`调用次数需要平衡，如果重复调用dispatch_resume则会崩溃,因为重复调用会让`dispatch_resume`代码里if分支不成立，从而执行了DISPATCH_CLIENT_CRASH("Over-resume of an object")导致崩溃。
3. source在suspend状态下，如果直接设置source = nil或者重新创建source都会造成crash。正确的方式是在resume状态下调用dispatch_source_cancel(source)后再重新创建。

## 4.10 dispatch_after(延迟执行)

### 4.10.1 使用

```objectivec
/*
获取精确时间点
typedef uint64_t dispatch_time_t;
		#define DISPATCH_TIME_NOW (0ull)
		#define DISPATCH_TIME_FOREVER (~0ull)
* 参数1: 开始时间  DISPATCH_TIME_NOW(现在的时间)
* 参数2：多久后  数值和NSEC_PER_SEC的乘积得到单位为毫微秒的数值，ull是C语言的数值字面量，是显示表明类型时使用的字符串（表示‘unsigned long long’） ，NSEC_PER_MSEC表示毫秒单位
*/
dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW , 3ull * NSEC_PER_SEC);

/*
 * 参数1：指定时间用的dispatch_time_t类型的值，dispatch_time_t类型的值使用dispatch_time函数或者dispatch _walltime函数生成
 * 参数2：指定要追加处理的Dispatch Queue
 * 参数3：指定记述要执行处理的Block
 */
dispatch_after(time , dispatch_get_main_queue(), ^{
  NSLog(@"waited at least three seconds ");
});
```

注意：

- dispatch_after 函数并不是在指定时间后执行处理，而只是在指定时间追加处理到 Dispatch Queue，上述代码与3秒后用 dispatch_async 函数追加 Block 到 Main Dispatch Queue 的相同。
- 因为 Main Dispatch Queue 在主线程的 RunLoop 中执行，所以在比如每隔 1/60 秒执行的 RunLoop 中，Block 最快在3秒后执行，最慢在 3秒+1/60秒 后执行，并且在 Main Dispatch Queue 有大量处理追加或主线程的处理本身有延迟是，这个时间会更长。

`dispatch_walltime` 函数由 POSLX 中使用的 struct timespec 类型的时间得到 dispatch _time_t 类型的值。

`dispatch_time` 函数通常用于计算相对时间。

`dispatch_walltime` 函数用于计算绝对时间，需要指定精确时间参数，可作为粗略的闹钟功能使用。

### 4.10.2 原理

`dispatch_after`是基于Dispatch Source的定时器实现的，函数内部直接调用`dispatch_after_f`，代码如下：

```c++
void dispatch_after_f(dispatch_time_t when, dispatch_queue_t queue, void *ctxt,
        dispatch_function_t func) {
    uint64_t delta, leeway;
    dispatch_source_t ds;
    //屏蔽DISPATCH_TIME_FOREVER类型
    if (when == DISPATCH_TIME_FOREVER) {
#if DISPATCH_DEBUG
        DISPATCH_CLIENT_CRASH(
                "dispatch_after_f() called with 'when' == infinity");
#endif
        return;
    }
    delta = _dispatch_timeout(when);
    if (delta == 0) {
        return dispatch_async_f(queue, ctxt, func);
    }
    leeway = delta / 10; // <rdar://problem/13447496>
    if (leeway < NSEC_PER_MSEC) leeway = NSEC_PER_MSEC;
    if (leeway > 60 * NSEC_PER_SEC) leeway = 60 * NSEC_PER_SEC;

    // this function can and should be optimized to not use a dispatch source
    //创建dispatch_source
    ds = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_assert(ds);

    dispatch_continuation_t dc = _dispatch_continuation_alloc();
    dc->do_vtable = (void *)(DISPATCH_OBJ_ASYNC_BIT | DISPATCH_OBJ_BARRIER_BIT);
    dc->dc_func = func;
    dc->dc_ctxt = ctxt;
    dc->dc_data = ds;
    //将dispatch_continuation_t存储到上下文中
    dispatch_set_context(ds, dc);
    //设置timer并启动
    dispatch_source_set_event_handler_f(ds, _dispatch_after_timer_callback);
    dispatch_source_set_timer(ds, when, DISPATCH_TIME_FOREVER, leeway);
    dispatch_resume(ds);
}
```

timer到时之后，会调用`_dispatch_after_timer_callback`函数，在这里取出上下文里的block并执行：

```c++
void _dispatch_after_timer_callback(void *ctxt) {
    dispatch_continuation_t dc = ctxt, dc1;
    dispatch_source_t ds = dc->dc_data;
    dc1 = _dispatch_continuation_free_cacheonly(dc);
    //执行任务的block并执行
    _dispatch_client_callout(dc->dc_ctxt, dc->dc_func);
    //清理数据
    dispatch_source_cancel(ds);
    dispatch_release(ds);
    if (slowpath(dc1)) {
        _dispatch_continuation_free_to_cache_limit(dc1);
    }
}
```

# 五、参考链接

- [iOS开发笔记 — 小专栏](https://xiaozhuanlan.com/iOSDevNotes)