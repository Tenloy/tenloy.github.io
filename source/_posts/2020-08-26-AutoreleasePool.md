---
title: AutoreleasePool
date: 2020-08-26 06:19:21
urlname: AutoreleasePool.html
tags:
    - AutoreleasePool
categories:
	- iOS
---

## 一、Autorelease简介

iOS开发中的Autorelease机制是为了延时释放对象。自动释放的概念看上去很像ARC，但实际上这更类似于C语言中自动变量的特性。

自动变量：在超出变量作用域后将被废弃；
 自动释放池：在超出释放池生命周期后，向其管理的对象实例的发送`release`消息。

### 1.1 MRC下使用自动释放池

在MRC环境中使用自动释放池需要用到`NSAutoreleasePool`对象，其生命周期就相当于C语言变量的作用域。对于所有调用过`autorelease`方法的对象，在废弃`NSAutoreleasePool`对象时，都将调用`release`实例方法。用源代码表示如下：

```swift
//MRC环境下的测试：
//第一步：生成并持有释放池NSAutoreleasePool对象;
NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

//第二步：调用对象的autorelease实例方法;
id obj = [[NSObject alloc] init];
[obj autorelease];

//第三步：废弃NSAutoreleasePool对象;
[pool drain];   //向pool管理的所有对象发送消息，相当于[obj release]

//obi已经释放，再次调用会崩溃(Thread 1: EXC_BAD_ACCESS (code=EXC_I386_GPFLT))
NSLog(@"打印obj：%@", obj); 
```

理解`NSAutoreleasePool`对象的生命周期，如下图所示：

<img src="/images/RunLoop/AutoreleasePool5.png" width = "50%" alt="" align=center />

### 1.2 ARC下使用自动释放池

ARC环境不能使用`NSAutoreleasePool`类也不能调用`autorelease`方法，代替它们实现对象自动释放的是`@autoreleasepool`块和`__autoreleasing`修饰符。比较两种环境下的代码差异如下图：

<img src="/images/RunLoop/AutoreleasePool4.png" width = "60%" alt="" align=center />

如图所示，`@autoreleasepool`块替换了`NSAutoreleasePoool`类对象的生成、持有及废弃这一过程。而附有`__autoreleasing`修饰符的变量替代了`autorelease`方法，将对象注册到了`Autoreleasepool`；由于ARC的优化，`__autorelease`是可以被省略的，所以简化后的ARC代码如下：

```swift
//ARC环境下的测试：
@autoreleasepool {
    id obj = [[NSObject alloc] init];
    NSLog(@"打印obj：%@", obj); 
}
```

显式使用`__autoreleasing`修饰符的情况非常少见，这是因为ARC的很多情况下，即使是不显式的使用`__autoreleasing`，也能实现对象被注册到释放池中。主要包括以下几种情况：

1. 编译器会进行优化，检查方法名是否以`alloc/new/copy/mutableCopy`开始，如果不是则自动将返回对象注册到`Autoreleasepool`;
2. 访问附有`__weak`修饰符的变量时，实际上必定要访问注册到`Autoreleasepool`的对象，即会自动加入`Autoreleasepool`;
3. id的指针或对象的指针(id*，NSError **)，在没有显式地指定修饰符时候，会被默认附加上`__autoreleasing`修饰符，加入`Autoreleasepool`

**注意：**如果编译器版本为LLVM.3.0以上，即使ARC无效`@autoreleasepool`块也能够使用；如下源码所示：

```swift
//MRC环境下的测试：
@autoreleasepool{
    id obj = [[NSObject alloc] init];
    [obj autorelease];
}
```

## 二、AutoRelease原理

### 2.1 使用@autoreleasepool{}

我们在`main`函数中写入自动释放池相关的测试代码如下：

```swift
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"Hello, World!");
    }
    return 0;
}
```

为了探究释放池的底层实现，我们在终端使用`clang -rewrite-objc + 文件名`命令将上述OC代码转化为C++源码：

```c
int main(int argc, const char * argv[]) {
    /* @autoreleasepool */
    {
        __AtAutoreleasePool __autoreleasepool;
        NSLog((NSString *)&__NSConstantStringImpl__var_folders_3f_crl5bnj956d806cp7d3ctqhm0000gn_T_main_d37e0d_mi_0);
     }//大括号对应释放池的作用域
     
     return 0;
}
```

在经过编译器`clang`命令转化后，我们看到的所谓的`@autoreleasePool`块，其实对应着`__AtAutoreleasePool`的结构体。

### 2.2 分析结构体__AtAutoreleasePool的具体实现

在源码中找到`__AtAutoreleasePool`结构体的实现代码，具体如下：

```c
extern "C" __declspec(dllimport) void * objc_autoreleasePoolPush(void);
extern "C" __declspec(dllimport) void objc_autoreleasePoolPop(void *);

struct __AtAutoreleasePool {
  __AtAutoreleasePool() {atautoreleasepoolobj = objc_autoreleasePoolPush();}
  ~__AtAutoreleasePool() {objc_autoreleasePoolPop(atautoreleasepoolobj);}
  void * atautoreleasepoolobj;
};
__AtAutoreleasePool`结构体包含了：构造函数、析构函数和一个边界对象；
 构造函数内部调用：`objc_autoreleasePoolPush()`方法，返回边界对象`atautoreleasepoolobj`
 析构函数内部调用：`objc_autoreleasePoolPop()`方法，传入边界对象`atautoreleasepoolobj
```

分析`main`函数中`__autoreleasepool`结构体实例的生命周期是这样的：
 `__autoreleasepool`是一个自动变量，其构造函数是在程序执行到声明这个对象的位置时调用的，而其析构函数则是在程序执行到离开这个对象的作用域时调用。所以，我们可以将上面`main`函数的代码简化如下：

```swift
int main(int argc, const char * argv[]) {
    /* @autoreleasepool */ {
        void *atautoreleasepoolobj = objc_autoreleasePoolPush();
        NSLog((NSString *)&__NSConstantStringImpl__var_folders_kb_06b822gn59df4d1zt99361xw0000gn_T_main_d39a79_mi_0);
        objc_autoreleasePoolPop(atautoreleasepoolobj);
    }
    return 0;
}
```

### 2.3 objc_autoreleasePoolPush与objc_autoreleasePoolPop

进一步观察自动释放池构造函数与析构函数的实现，其实它们都只是对`AutoreleasePoolPage`对应静态方法`push`和`pop`的封装

```c
void *objc_autoreleasePoolPush(void) {
    return AutoreleasePoolPage::push();
}

void objc_autoreleasePoolPop(void *ctxt) {
    AutoreleasePoolPage::pop(ctxt);
}
```

### 2.4 理解AutoreleasePoolPage

`AutoreleasePoolPage`是一个C++中的类，打开`Runtime`的源码工程，在`NSObject.mm`文件中可以找到它的定义，摘取其中的关键代码如下：

```c
//大致在641行代码开始
class AutoreleasePoolPage {
#   define EMPTY_POOL_PLACEHOLDER ((id*)1)  //空池占位
#   define POOL_BOUNDARY nil                //边界对象(即哨兵对象）
    static pthread_key_t const key = AUTORELEASE_POOL_KEY;
    static uint8_t const SCRIBBLE = 0xA3;  // 0xA3A3A3A3 after releasing
    static size_t const SIZE = 
#if PROTECT_AUTORELEASEPOOL
        PAGE_MAX_SIZE;  // must be multiple of vm page size
#else
        PAGE_MAX_SIZE;  // size and alignment, power of 2
#endif
    static size_t const COUNT = SIZE / sizeof(id);
    magic_t const magic;                  //校验AutoreleasePagePoolPage结构是否完整
    id *next;                             //指向新加入的autorelease对象的下一个位置，初始化时指向begin()
    pthread_t const thread;               //当前所在线程，AutoreleasePool是和线程一一对应的
    AutoreleasePoolPage * const parent;   //指向父节点page，第一个结点的parent值为nil
    AutoreleasePoolPage *child;           //指向子节点page，最后一个结点的child值为nil
    uint32_t const depth;                 //链表深度，节点个数
    uint32_t hiwat;                       //数据容纳的一个上限
    //......
};
```

其实，**每个自动释放池都是是由若干个`AutoreleasePoolPage`组成的双向链表结构**，如下图所示:

<img src="/images/RunLoop/AutoreleasePool3.png" width = "90%" alt="" align=center />

`AutoreleasePoolPage`中拥有`parent`和`child`指针，分别指向上一个和下一个`page`；当前一个`page`的空间被占满(每个`AutorelePoolPage`的大小为4096字节)时，就会新建一个`AutorelePoolPage`对象并连接到链表中，后来的  Autorelease对象也会添加到新的`page`中；

另外，当`next== begin()`时，表示`AutoreleasePoolPage`为空；当`next == end()`，表示`AutoreleasePoolPage`已满。

### 2.5 理解哨兵对象/边界对象(POOL_BOUNDARY)的作用

在`AutoreleasePoolPage`的源码中，我们很容易找到边界对象(哨兵对象)的定义：

```objectivec
#define POOL_BOUNDARY nil
```

边界对象其实就是`nil`的别名，而它的作用事实上也就是为了起到一个标识的作用。

每当自动释放池初始化调用`objc_autoreleasePoolPush`方法时，总会通过`AutoreleasePoolPage`的`push`方法，将`POOL_BOUNDARY`放到当前`page`的栈顶，并且返回这个边界对象；

而在自动释放池释放调用`objc_autoreleasePoolPop`方法时，又会将边界对象以参数传入，这样自动释放池就会向释放池中对象发送`release`消息，直至找到第一个边界对象为止。

### 2.6 理解objc_autoreleasePoolPush方法

经过前面的分析，`objc_autoreleasePoolPush`最终调用的是    `AutoreleasePoolPage`的`push`方法，该方法的具体实现如下：

```c
static inline void *push() {
   return autoreleaseFast(POOL_BOUNDARY);
}

static inline id *autoreleaseFast(id obj)
{
   AutoreleasePoolPage *page = hotPage();
   if (page && !page->full()) {
       return page->add(obj);
   } else if (page) {
       return autoreleaseFullPage(obj, page);
   } else {
1.        return autoreleaseNoPage(obj);
   }
}

//压栈操作：将对象加入AutoreleaseNoPage并移动栈顶的指针
id *add(id obj) {
    id *ret = next;
    *next = obj;
    next++;
    return ret;
}

//当前hotPage已满时调用
static id *autoreleaseFullPage(id obj, AutoreleasePoolPage *page) {
    do {
        if (page->child) page = page->child;
        else page = new AutoreleasePoolPage(page);
    } while (page->full());

    setHotPage(page);
    return page->add(obj);
}

//当前hotpage不存在时调用
static id *autoreleaseNoPage(id obj) {
    AutoreleasePoolPage *page = new AutoreleasePoolPage(nil);
    setHotPage(page);

    if (obj != POOL_SENTINEL) {
        page->add(POOL_SENTINEL);
    }

    return page->add(obj);
}
```

观察上述代码，每次调用`push`其实就是创建一个新的AutoreleasePool，在对应的`AutoreleasePoolPage`中插入一个`POOL_BOUNDARY` ，并且返回插入的`POOL_BOUNDARY` 的内存地址。`push`方法内部调用的是`autoreleaseFast`方法，并传入边界对象(`POOL_BOUNDARY`)。`hotPage`可以理解为当前正在使用的`AutoreleasePoolPage`。

自动释放池最终都会通过`page->add(obj)`方法将边界对象添加到释放池中，而这一过程在`autoreleaseFast`方法中被分为三种情况：

1. 当前`page`存在且不满，调用`page->add(obj)`方法将对象添加至`page`的栈中，即`next`指向的位置
2. 当前`page`存在但是已满，调用`autoreleaseFullPage`初始化一个新的`page`，调用`page->add(obj)`方法将对象添加至`page`的栈中
3. 当前`page`不存在时，调用`autoreleaseNoPage`创建一个`hotPage`，再调用`page->add(obj)` 方法将对象添加至`page`的栈中

### 2.7 objc_autoreleasePoolPop方法

AutoreleasePool的释放调用的是`objc_autoreleasePoolPop`方法，此时需要传入边界对象作为参数。这个边界对象正是每次执行`objc_autoreleasePoolPush`方法返回的对象`atautoreleasepoolobj`；

同理，我们找到`objc_autoreleasePoolPop`最终调用的方法，即`AutoreleasePoolPage`的`pop`方法，该方法的具体实现如下：

```c
static inline void pop(void *token)   //POOL_BOUNDARY的地址
{
    AutoreleasePoolPage *page;
    id *stop;

    page = pageForPointer(token);   //通过POOL_BOUNDARY找到对应的page
    stop = (id *)token;
    if (DebugPoolAllocation  &&  *stop != POOL_SENTINEL) {
        // This check is not valid with DebugPoolAllocation off
        // after an autorelease with a pool page but no pool in place.
        _objc_fatal("invalid or prematurely-freed autorelease pool %p; ", 
                    token);
    }

    if (PrintPoolHiwat) printHiwat();   // 记录最高水位标记

    page->releaseUntil(stop);   //向栈中的对象发送release消息，直到遇到第一个哨兵对象

    // memory: delete empty children
    // 删除空掉的节点
    if (DebugPoolAllocation  &&  page->empty()) {
        // special case: delete everything during page-per-pool debugging
        AutoreleasePoolPage *parent = page->parent;
        page->kill();
        setHotPage(parent);
    } else if (DebugMissingPools  &&  page->empty()  &&  !page->parent) {
        // special case: delete everything for pop(top) 
        // when debugging missing autorelease pools
        page->kill();
        setHotPage(nil);
    } 
    else if (page->child) {
        // hysteresis: keep one empty child if page is more than half full
        if (page->lessThanHalfFull()) {
            page->child->kill();
        }
        else if (page->child->child) {
            page->child->child->kill();
        }
    }
}
```

上述代码中，首先根据传入的边界对象地址找到边界对象所处的`page`；然后选择当前`page`中最新加入的对象一直向前清理，可以向前跨越若干个`page`，直到边界所在的位置；清理的方式是向这些对象发送一次`release`消息，使其引用计数减一；

另外，清空`page`对象还会遵循一些原则：

1. 如果当前的`page`中存放的对象少于一半，则子`page`全部删除；
2. 如果当前当前的`page`存放的多余一半（意味着马上将要满），则保留一个子`page`，节省创建新`page`的开销;

### 2.8 autorelease方法

上述是对自动释放池整个生命周期的分析，现在我们来理解延时释放对象`autorelease`方法的实现，首先查看该方法的调用栈：

```objectivec
- [NSObject autorelease]
└── id objc_object::rootAutorelease()
    └── id objc_object::rootAutorelease2()
        └── static id AutoreleasePoolPage::autorelease(id obj)
            └── static id AutoreleasePoolPage::autoreleaseFast(id obj)
                ├── id *add(id obj)
                ├── static id *autoreleaseFullPage(id obj, AutoreleasePoolPage *page)
                │   ├── AutoreleasePoolPage(AutoreleasePoolPage *newParent)
                │   └── id *add(id obj)
                └── static id *autoreleaseNoPage(id obj)
                    ├── AutoreleasePoolPage(AutoreleasePoolPage *newParent)
                    └── id *add(id obj)
```

如上所示，`autorelease`方法最终也会调用上面提到的 `autoreleaseFast`方法，将当前对象加到`AutoreleasePoolPage`中。关于`autoreleaseFast`的分析这里不再累述，我们主要来考虑一下两次调用的区别：

`autorelease`函数和`push`函数一样，关键代码都是调用`autoreleaseFast`函数向自动释放池的链表栈中添加一个对象，不过`push`函数入栈的是一个边界对象，而`autorelease`函数入栈的是一个具体的Autorelease的对象。

## 三、AutoreleasePool与NSThread、NSRunLoop的关系

由于`AppKit`和`UIKit`框架的优化，我们很少需要显式的创建一个自动释放池块。这其中就涉及到`AutoreleasePool`与`NSThread`、`NSRunLoop`的关系。

### 3.1 RunLoop和NSThread的关系

`RunLoop`是用于控制线程生命周期并接收事件进行处理的机制，其实质是一个`do-While`循环。在苹果文档找到关于[NSRunLoop](https://links.jianshu.com/go?to=https%3A%2F%2Fdeveloper.apple.com%2Fdocumentation%2Ffoundation%2Fnsrunloop%23%2F%2Fapple_ref%2Fdoc%2Fconstant_group%2FRun_Loop_Modes)的介绍如下：

> Your application neither creates or explicitly manages NSRunLoop objects. Each NSThread object—including the application’s main thread—has an NSRunLoop object automatically created for it as needed. If you need to access the current thread’s run loop, you do so with the class method currentRunLoop.

总结`RunLoop`与`NSThread`(线程)之间的关系如下：

1. `RunLoop`与线程是一一对应关系，每个线程(包括主线程)都有一个对应的`RunLoop`对象；其对应关系保存在一个全局的Dictionary里；
2. 主线程的`RunLoop`默认由系统自动创建并启动；而其他线程在创建时并没有`RunLoop`，若该线程一直不主动获取，就一直不会有`RunLoop`；
3. 苹果不提供直接创建`RunLoop`的方法；所谓其他线程`Runloop`的创建其实是发生在第一次获取的时候，系统判断当前线程没有`RunLoop`就会自动创建；
4. 当前线程结束时，其对应的`Runloop`也被销毁；

### 3.2 RunLoop和AutoreleasePool的关系

在[苹果文档](https://links.jianshu.com/go?to=https%3A%2F%2Fdeveloper.apple.com%2Flibrary%2Fios%2Fdocumentation%2FCocoa%2FReference%2FFoundation%2FClasses%2FNSAutoreleasePool_Class%2Findex.html%23%2F%2Fapple_ref%2Fdoc%2Fuid%2FTP40003623)中找到两者关系的介绍如下：

> The Application Kit creates an autorelease pool on the main thread at the beginning of every cycle of the event loop, and drains it at the end, thereby releasing any autoreleased objects generated while processing an event.

如上所述，主线程的`NSRunLoop`在监测到事件响应开启每一次`event loop`之前，会自动创建一个`autorelease pool`，并且会在`event loop`结束的时候执行`drain`操作，释放其中的对象。

### 3.3 Thread和AutoreleasePool的关系

在[苹果文档](https://links.jianshu.com/go?to=https%3A%2F%2Fdeveloper.apple.com%2Flibrary%2Fios%2Fdocumentation%2FCocoa%2FReference%2FFoundation%2FClasses%2FNSAutoreleasePool_Class%2Findex.html%23%2F%2Fapple_ref%2Fdoc%2Fuid%2FTP40003623)中找到两者关系的介绍如下：

> Each thread (including the main thread) maintains its own stack of NSAutoreleasePool objects (see Threads). As new pools are created, they get added to the top of the stack. When pools are deallocated, they are removed from the stack. Autoreleased objects are placed into the top autorelease pool for the current thread. When a thread terminates, it automatically drains all of the autorelease pools associated with itself.

如上所述， 包括主线程在内的所有线程都维护有它自己的自动释放池的堆栈结构。新的自动释放池被创建的时候，它们会被添加到栈的顶部，而当池子销毁的时候，会从栈移除。对于当前线程来说，Autoreleased对象会被放到栈顶的自动释放池中。当一个线程线程停止，它会自动释放掉与其关联的所有自动释放池。

## 四、AutoreleasePool在主线程上的释放时机

### 4.1 理解主线程上的自动释放过程

分析主线程`RunLoop`管理自动释放池并释放对象的详细过程，我们在如下Demo中的主线程中设置断点，并执行lldb命令：`po [NSRunLoop currentRunLoop]`，具体效果如下：

<img src="/images/RunLoop/AutoreleasePool2.png" width = "70%" alt="" align=center />

我们看到主线程`RunLoop`中有两个与自动释放池相关的`Observer`，它们的 `activities`分别为`0x1`和`0xa0`这两个十六进制的数，转为二进制分别为`1`和`10100000`，对应`CFRunLoopActivity`的类型如下：

```c
/* Run Loop Observer Activities */
typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
    kCFRunLoopEntry = (1UL << 0),          //0x1，启动Runloop循环
    kCFRunLoopBeforeTimers = (1UL << 1),            
    kCFRunLoopBeforeSources = (1UL << 2),        
    kCFRunLoopBeforeWaiting = (1UL << 5),  //0xa0，即将进入休眠     
    kCFRunLoopAfterWaiting = (1UL << 6),   
    kCFRunLoopExit = (1UL << 7),           //0xa0，退出RunLoop循环  
    kCFRunLoopAllActivities = 0x0FFFFFFFU
    };
```

结合RunLoop监听的事件类型，分析主线程上自动释放池的使用过程如下：

1. App启动后，苹果在主线程`RunLoop`里注册了两个`Observer`，其回调都是 `_wrapRunLoopWithAutoreleasePoolHandler()`;
2. 第一个`Observer`监视的事件是`Entry`(即将进入Loop)，其回调内会调用 `_objc_autoreleasePoolPush()`创建自动释放池。`order = -2147483647`(即32位整数最小值)表示其优先级最高，可以保证创建释放池发生在其他所有回调之前;
3. 第二个`Observer`监视了两个事件`BeforeWaiting`(准备进入休眠)时调用`_objc_autoreleasePoolPop()`和`_objc_autoreleasePoolPush()`释放旧的池并创建新池；`Exit`(即将退出Loop) 时调用 `_objc_autoreleasePoolPop()`来释放自动释放池。`order = 2147483647`(即32位整数的最大值)表示其优先级最低，保证其释放池子发生在其他所有回调之后;
4. 在主线程执行的代码，通常是写在诸如事件回调、Timer回调内的。这些回调会被 `RunLoop`创建好的`AutoreleasePool`环绕着，所以不会出现内存泄漏，开发者也不必显示创建`AutoreleasePool`了;

最后，也可以结合图示理解主线程上自动释放对象的具体流程：

<img src="/images/RunLoop/AutoreleasePool.png" width = "70%" alt="" align=center />

1. 程序启动到加载完成后，主线程对应的`RunLoop`会停下来等待用户交互
2. 用户的每一次交互都会启动一次运行循环，来处理用户所有的点击事件、触摸事件。
3. `RunLoop`检测到事件后，就会创建自动释放池;
4. 所有的延迟释放对象都会被添加到这个池子中;
5. 在一次完整的运行循环结束之前，会向池中所有对象发送`release`消息，然后自动释放池被销毁;

### 4.2 测试主线程上的对象自动释放过程

下面的代码创建了一个Autorelease对象`string`，并且通过`weakString`进行弱引用(不增加引用计数，所以不会影响对象的生命周期)，具体如下：

```swift
@interface TestMemoryVC ()
@property (nonatomic,weak)NSString *weakString;
@end

@implementation TestMemoryVC
- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *string = [NSString stringWithFormat:@"%@",@"WUYUBEICHEN"];
    self.weakString = string;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSLog(@"viewWillAppear:%@", self.weakString);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSLog(@"viewDidAppear:%@", self.weakString);
}

@end

//打印结果：
//viewWillAppear:WUYUBEICHEN
//viewDidAppear:(null)
```

**代码分析：**自动变量的`string`在离开`viewDidLoad`的作用域后，会依靠当前主线程上的`RunLoop`迭代自动释放。最终`string`对象在`viewDidAppear`方法执行前被释放(`RunLoop`完成此次迭代)。

## 五、AutoreleasePool子线程上的释放时机

子线程默认不开启`RunLoo`p，那么其中的延时对象该如何释放呢？其实这依然要从`Thread`和`AutoreleasePool`的关系来考虑：

> Each thread (including the main thread) maintains its own stack of NSAutoreleasePool objects.

也就是说，每一个线程都会维护自己的 `Autoreleasepool`栈，所以子线程虽然默认没有开启`RunLoop`，但是依然存在`AutoreleasePool`，在子线程退出的时候会去释放`autorelease`对象。

前面讲到过，ARC会根据一些情况进行优化，添加`__autoreleasing`修饰符，其实这就相当于对需要延时释放的对象调用了`autorelease`方法。从源码分析的角度来看，如果子线程中没有创建`AutoreleasePool` ，而一旦产生了`Autorelease`对象，就会调用`autoreleaseNoPage`方法自动创建`hotpage`，并将对象加入到其栈中。所以，一般情况下，子线程中即使我们不手动添加自动释放池，也不会产生内存泄漏。

## 六、AutoreleasePool需要手动添加的情况

尽管ARC已经做了诸多优化，但是有些情况我们必须手动创建`AutoreleasePool`，而其中的延时对象将在当前释放池的作用域结束时释放。[苹果文档](https://links.jianshu.com/go?to=https%3A%2F%2Fdeveloper.apple.com%2Flibrary%2Farchive%2Fdocumentation%2FCocoa%2FConceptual%2FMemoryMgmt%2FArticles%2FmmAutoreleasePools.html%23%2F%2Fapple_ref%2Fdoc%2Fuid%2F20000047)中说明了三种情况，我们可能会需要手动添加自动释放池：

1. 编写的不是基于UI框架的程序，例如命令行工具；
2. 通过循环方式创建大量临时对象；
3. 使用非Cocoa程序创建的子线程；

而在ARC环境下的实际开发中，我们最常遇到的也是第二种情况，以下面的代码为例：

```swift
- (void)viewDidLoad {
    [super viewDidLoad];
    for (int i = 0; i < 1000000; i++) {
        NSObject *obj = [[NSObject alloc] init];
        NSLog(@"打印obj：%@", obj);
    }
 }
```

上述代码中，`obj`因为离开作用域所以会被加入最近一次创建的自动释放池中，而这个释放池就是主线程上的`RunLoop`管理的；因为`for`循环在当前线程没有执行完毕，`Runloop`也就没有完成当前这一次的迭代，所以导致大量对象被延时释放。释放池中的对象将会在`viewDidAppear`方法执行前就被销毁。在此情况下，我们就有必要通过手动干预的方式及时释放不需要的对象，减少内存消耗；优化的代码如下：

```swift
- (void)viewDidLoad {
    [super viewDidLoad];
    for (int i = 0; i < 1000000; i++) {
        @autoreleasepool{
             NSObject *obj = [[NSObject alloc] init];
             NSLog(@"打印obj：%@", obj);
        }
    }
 }
```