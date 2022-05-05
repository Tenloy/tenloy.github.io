---
title: (六) Mach-O 文件的动态链接、库、Dyld(含dlopen)
date: 2021-09-27 14:26:09
urlname: compile-dynamic-link.html
tags:
categories:
  - 编译链接与装载
---

## 一、动态链接
动态链接的基本思想是把程序按照模块拆分成各个相对独立部分，在程序运行时才将它们链接在一起形成一个完整的程序，而不是像静态链接一样把所有的程序模块都链接成一个个单独的可执行文件。

动态链接涉及运行时的链接及多个文件的装载，必需要有操作系统的支持，因为动态链接的情况下，进程的虚拟地址空间的分布会比静态链接情况下更为复杂，还有一些存储管理、内存共享、进程线程等机制在动态链接下也会有一些微妙的变化。目前主流的操作系统几乎都支持动态链接这种方式。

link 这个过程就是将加载进来的二进制变为可用状态的过程。简单来说就是：`rebase => binding`。先来介绍动态链接中的几个概念：

### 1.1 rebase

rebase就是指针修正的过程。

一个mach-o的二进制文件中，包含了**text**段和**data**段。而**data**段中的数据也会存在**引用**关系。 我们知道在代码中，我们可以用**指针**来引用，那么在一个文件中怎么代表引用呢，那就是**偏移**(相对于text段开始的偏移)。 

当二进制加载到内存中的时候，起始地址就是申请的内存的起始地址（slide)，不会是0，那么如何再能够找到这些引用的正确内存位置呢？ 把**偏移**加上(slide)就好了。 这个过程就是rebase的过程。

<img src="/images/compilelink/38.png" alt="38" style="zoom:70%;" />

### 1.2 bind

> “决议”更倾向于静态链接，而“绑定”更倾向于动态链接，即它们所使用的范围不一样。

bind就是符号绑定的过程。

为什么要bind? 因为符号在不同的库里面。

举个简单的例子，我们代码里面调用了 `NSClassFromString`. 但是`NSClassFromString`的代码和符号都是在 `Foundation.framework` 这个动态库里面。而在程序未加载之前，我们的代码是不知道`NSLog`在哪里的，于是编译器就编译了一个 **stub** 来调用 `NSClassFromString`:

<img src="/images/compilelink/39.png" alt="39" style="zoom:97%;" />

可以看到，我们的代码里面直接从 pc + 0x3701c的地方取出来一个值，然后直接br， 也就是认为这个值就是 `NSClassFromString`的真实地址了。我们再看看这个位置的值是啥：

<img src="/images/compilelink/40.png" alt="40" style="zoom:100%;" />

也就是说，这块地址的8个字节会在**bind**之后存入的就是 `NSClassFromString`的代码地址， 那么就实现了真正调用 `NSClassFromString`的过程。

上面我们知道了为啥要**bind**. 那是如何bind的呢？ bind又分为哪些呢？

#### 1.2.1 怎么bind

首先 mach-o 的 LoadCommand里面的会有一个cmd来描述 dynamic loader info，数据结构与示例如下：

```c++
//以下的偏移量是相对于目标文件/可执行文件的起始地址，注意后者的起始地址一般不会是0，寻址时要加上
struct dyld_info_command {
   uint32_t   cmd;            /* LC_DYLD_INFO or LC_DYLD_INFO_ONLY */
   uint32_t   cmdsize;        /* sizeof(struct dyld_info_command) */
   uint32_t   rebase_off;     /* file offset to rebase info  */
   uint32_t   rebase_size;    /* size of rebase info   */
   uint32_t   bind_off;       /* file offset to binding info   */
   uint32_t   bind_size;      /* size of binding info  */
   /*
    Some C++ programs require dyld to unique symbols so that all images in the process use the same copy of some code/data. 
    This step is done after binding. 
    The content of the weak_bind info is an opcode stream like the bind_info. But it is sorted alphabetically by symbol name. This enable dyld to walk all images with weak binding information in order and look for collisions. 
    If there are no collisions, dyld does no updating. That means that some fixups are also encoded in the bind_info. 
    For instance, all calls to "operator new" are first bound to libstdc++.dylib using the information in bind_info. Then if some image overrides operator new that is detected when the weak_bind information is processed and the call to operator new is then rebound.
    */
   uint32_t   weak_bind_off;  /* file offset to weak binding info   */
   uint32_t   weak_bind_size; /* size of weak binding info  */
   uint32_t   lazy_bind_off;  /* file offset to lazy binding info */
   uint32_t   lazy_bind_size; /* size of lazy binding infs */
   uint32_t   export_off;     /* file offset to export info */
   uint32_t   export_size;    /* size of export infs */
};
```

解析出来会得到这样的信息：

- `rebase`：就是针对 “mach-o在加载到虚拟内存中不是固定的首地址” 这一现象做数据修正的过程。一般可执行文件在没有ASLR造成的首地址不固定的情况下，装载进虚拟地址中的首地址都是固定的，比如：Linux下一般都是`0x08040000`，Windows下一般都是`0x0040000`，Mach-O的TEXT地址在__PageZero之后的`0x100000000`地址.
- `binding`：就是将这个二进制调用的外部符号进行绑定的过程。 比如我们objc代码中需要使用到NSObject，即符号`_OBJC_CLASS_$_NSObject`，但是这个符号又不在我们的二进制中，在系统库 Foundation.framework中，因此就需要binding这个操作将对应关系绑定到一起。
- `lazyBinding`：就是在加载动态库的时候不会立即binding，当时当第一次调用这个方法的时候再实施binding。 做到的方法也很简单： 通过`dyld_stub_binder`这个符号来做。 lazy binding的方法第一次会调用到dyld_stub_binder, 然后dyld_stub_binder负责找到真实的方法，并且将地址bind到桩上，下一次就不用再bind了。
- `weakBinding`：OC的代码貌似不会编译出`Weak Bind`. 目前遇到的`Weak Bind`都是C++的 `template` 的方法。特点就是：Weak bind的符号每加载进来二进制都会bind到最新的符号上。比如2个动态库里面都有同样的`weak bind`符号，那么所有的的符号引用都会bind到后加载进来的那个符号上。

<img src="/images/compilelink/41.png" alt="41" style="zoom:90%;" />

可以看到，这里面记录了二进制data段里面哪些是 rebase信息，哪些是binding信息：

<img src="/images/compilelink/42.png" alt="42" style="zoom:78%;" />

可以看到binding info的数据结构，bind的过程根据不同的opcode解析出不同的信息，在opcode为`BIND_OPCODE_DO_BIND`的时候，会执行`bindLocation`来进行bind。

截取了 bindLocation 的代码：

```c++
uintptr_t ImageLoaderMachO::bindLocation(const LinkContext& context,...){
    //...
    // do actual update
    uintptr_t* locationToFix = (uintptr_t*)location;
    uint32_t* loc32;
    uintptr_t newValue = value+addend;
    uint32_t value32;
    switch (type) {
        case BIND_TYPE_POINTER:
            // test first so we don't needless dirty pages
            if ( *locationToFix != newValue )
                *locationToFix = newValue;
            break;
        case BIND_TYPE_TEXT_ABSOLUTE32:
            loc32 = (uint32_t*)locationToFix;
            value32 = (uint32_t)newValue;
            if ( *loc32 != value32 )
                *loc32 = value32;
            break;
        case BIND_TYPE_TEXT_PCREL32:
            loc32 = (uint32_t*)locationToFix;
            value32 = (uint32_t)(newValue - (((uintptr_t)locationToFix) + 4));
            if ( *loc32 != value32 )
                *loc32 = value32;
            break;
        default:
            dyld::throwf("bad bind type %d", type);
    }
    //...
}
```

可以看出， bind过程也不是单纯的就是把符号地址填过来就好了， 还有type和addend的逻辑。不过一般不多见，大部分都是`BIND_TYPE_POINTER`.

addend 一般用于要bind某个数组中的某个子元素时，记录这个子元素在数组的偏移。

#### 1.2.2 Lazy Bind

延迟加载是为了启动速度。上面看到bind的过程，发现bind的过程需要查到对应的符号再进行bind. 如果在启动的时候，所有的符号都立即bind成功，那么势必拖慢启动速度。

其实很多符号都是LazyBind的。就是第一次调用到才会真正的bind.

其实刚才截图的 `imp___la_symbol_ptr__objc_getClass` 就是一个 LazyBind 的符号。 图中的 0x10d6e8 指向了 `stub_helper` 这个section中的代码。

<img src="/images/compilelink/43.png" alt="43" style="zoom:90%;" />

如上图中

- 先取了 `0x10d6f0` 的 4个字节数据存入 w16. 这个数据其实是 lazy bind info段的偏移
- 然后走到 0x10d6d0, 取出 ImageLoader cache, 存入 x17
- 把 lazy bind info offset 和 ImageLoaderCache 存入栈上。
- 然后取出 dyld_stub_binder的地址，存入x16. 跳转 dyld_stub_binder
- dyld_stub_binder 会根据传入的 lazy bind info的 offset来执行真正的bind. bind结束后，刚才看到的 `0x10d6e8` 这个地址就变成了 `NSClassFromString`。就完成了LazyBind的过程。

`dyld_stub_binder`的源码此处不再展示。

#### 1.2.3 Weak Bind

OC的代码貌似不会编译出`Weak Bind`. 目前遇到的`Weak Bind`都是C++的 `template` 的方法。特点就是：Weak bind的符号每加载进来二进制都会bind到最新的符号上。比如2个动态库里面都有同样的`weak bind`符号，那么所有的的符号引用都会bind到后加载进来的那个符号上。

## 二、库: 静态库和动态库
库(Library)，是我们在开发中的重要角色，库的作用在于代码共享、模块分割以及提升良好的工程管理实践。说白了就是一段编译好的二进制代码，加上头文件就可以供别人使用。

为什么要用库？一种情况是某些代码需要给别人使用，但是我们不希望别人看到源码，就需要以库的形式进行封装，只暴露出头文件(**静态库和动态库的共同点就是不会暴露内部具体的代码信息**)。另外一种情况是，对于某些不会进行大的改动的代码，我们想减少编译的时间，就可以把它打包成库，因为库是已经编译好的二进制了，编译的时候只需要 Link 一下，不会浪费编译时间。

根据库在使用的时候 Link 时机或者说方式(静态链接、动态链接)，库分为静态库和动态库。

### 2.1 静态库

静态库即静态链接库（Windows 下的 .lib，linux 下的.a，Mac 下的 .a .framework）。之所以叫做静态，是因为静态库在`链接时`会被完整地拷贝一份到可执行文件中(会使最终的可执行文件体积增大)。被多个程序使用就会有多份冗余拷贝。如果更新静态库，需要重新编译一次可执行文件，重新链接新的静态库。

### 2.2 动态库

动态库即动态链接库。与静态库相反，动态库在编译时并不会被拷贝到可执行文件中，可执行文件中只会存储指向动态库的引用(使用了动态库的符号、及对应库的路径等)。等到程序`运行时`，动态库才会被真正加载进来，此时，先根据记录的库路径找到对应的库，再通过记录的名字符号找到绑定的地址。

动态库的优点是：
- **减少可执行文件体积**：相比静态链接，动态链接在编译时不需要打进去(不需要拷贝到每个可执行文件中)，所以可执行文件的体积要小很多。
- **代码共用**：很多程序都动态链接了这些 lib，但它们在内存和磁盘中中只有一份(因为这个原因，动态库也被称作**共享库**)。
- **易于维护**：使用动态库，可以不重新编译连接可执行程序的前提下，更新动态库文件达到更新应用程序的目的。

常见的可执行文件的形式：
- Linux系统中，ELF动态链接文件被称为**动态共享对象**(`DSO，Dynamic SharedObjects`)，简称共享对象，一般都是以 `.so` 为扩展名的一些文件；
- Windows系统中，动态链接文件被称为**动态链接库**(`Dynamical Linking Library`)，通常就是我们平时很常见的以 `.dll` 为扩展名的文件；
- OS X 和其他 UN\*X 不同，它的库不是“共享对象(.so)”，因为 OS X 和 ELF 不兼容，而且这个概念在 Mach-O 中不存在。OS 中的动态链接文件一般称为**动态库**文件，带有 `.dylib`、`.framework`及链接符号`.tbd`。
  - 库文件可以在 `/usr/lib` 目录下找到(这一点和其他所有的 UN*X 一样，不同的是在OS X 和 iOS 中没有/lib目录)，这些库已被设置全局可用。
  - 我们在使用系统的.dylib动态库时，经常发现没有头文件，其实这些库的头文件都位于一个已知位置，如`/usr/local/include`、`/usr/include`等 (后者文件夹在新系统中由SDK附带了，见 [/usr/include missing on macOS Catalina (with Xcode 11)](https://apple.stackexchange.com/questions/372032/usr-include-missing-on-macos-catalina-with-xcode-11) )。

- OS X 与其他 UN\*X 另一点不同是：没有`libc`。开发者可能熟悉其他 UN\*X 上的C运行时库(或Windows上的MSVCRT) 。但是在 OS X 上对应的库`/usr/lib/libc.dylib`只不过是指向`libSystem.B.dylib`的符号链接。
- 以C语言运行库为例，补充一下**运行库**的概念：任何一个C程序，它的背后都有一套庞大的代码来进行支撑，以使得该程序能够正常运行。这套代码至少包括入口函数，及其所依赖的函数所构成的函数集合。当然，它还理应包括各种标准库函数的实现。这样的一个代码集合称之为运行时库（Runtime Library）。而C语言的运行库，即被称为C运行库（CRT）。**运行库顾名思义是让程序能正常运行的一个库。**

### 2.3  两个非常重要的库 LibSystem、libobjc
libSystem 提供了 LibC(运行库) 的功能，还包含了在其他 UN\*X 上原本由其他一些库提供的功能，列几个熟知的：
- GCD libdispatch
- C语言库 libsystem_c
- Block libsystem_blocks
- 加密库(比如常见的md5函数) libcommonCrypto

还有些库(如数学库 libm、线程库 libpthread)虽然在/usr/lib中看到虽然有这些库的文件，但都是libSystem.B.dylib的替身/快捷方式，即都是指向libSystem的符号链接。

libSystem 库是系统上所有二进制代码的绝对先决条件，即所有的二进制文件都依赖这个库，不论是C、C++还是Objective-C的程序。这是因为这个库是对底层系统调用和内核服务的接口，如果没有这些接口就什么事也干不了。这个库还是/usr/ib/system目录下一些库的保护伞库(通过`LC_REEXPORT_LIB`加载命令重新导出了符号) 。

总结来说：**libSystem在运行库的基础上，增加了一些对底层系统调用和内核服务的抽象接口。**所以在下面的流程中，会发现**libSystem是先于其他动态库初始化**的。

**libobjc**与libsystem一样，都是默认添加的lib，包含iOS开发天天接触的objc runtime.

### 2.4 补充两个概念: 模块与image
- `程序模块`：从本质上讲，普通可执行程序和动态库中都包含指令和数据，这一点没有区别。在使用动态库的情况下，程序本身被分为了程序主要模块(`Program1`)和动态链接文件(`Lib.so` `Lib.dylib` `Lib.dll`)，但实际上它们都可以看作是整个程序的一个模块，所以当我们提到程序模块时可以指程序主模块也可以指动态链接库。
- `映像(image)` ，通常也是指这两者。可执行文件/动态链接文件，在装载时被直接映射到进程的虚拟地址空间中运行，它是进程的虚拟空间的映像，所以很多时候，也被叫做映像/镜像文件(Image File)。

### 2.5 .a/.dylib与.framework的区别
前者是纯二进制文件，文件不能直接使用，需要有.h文件的配合，后者除了二进制文件、头文件还有资源文件，代码可以直接导入使用(`.a + .h + sourceFile = .framework`)。

Framework 是苹果公司的 Cocoa/Cocoa Touch 程序中使用的一种资源打包方式，可以将代码文件、头文件、资源文件（nib/xib、图片、国际化文本）、说明文档等集中在一起，方便开发者使用。**Framework 其实是资源打包的方式，和静态库动态库的本质是没有什么关系**(**所以framework文件可以是静态库也可以是动态库，iOS 中用到的所有系统 framework 都是动态链接的**)。

在其它大部分平台上，动态库都可以用于不同应用间共享， 共享可执行文件，这就大大节省了内存。但是iOS平台在 iOS 8 之前，苹果不允许第三方框架使用动态方式加载，开发者可以使用的动态 Framework 只有苹果系统提供的 UIKit.Framework，Foundation.Framework 等。开发者要进行模块化，只能打包成静态库文件：`.a + 头文件`、`.framework`(这时候的 Framework 只支持打包成静态库的 Framework)，前种方式打包不够方便，使用时也比较麻烦，没有后者的便捷性。

iOS 8/Xcode 6 推出之后，允许开发者有条件地创建和使用动态库，支持了动态 Framework。开发者打包的动态 Framework 和系统的 UIKit.Framework 还是有很大区别。后者不需要拷贝到目标程序中，是一个链接。而前者在打包和提交 app 时会**被放到 app  main bundle 的根目录中，运行在沙盒里**，而不是系统中。也就是说，不同的 app 就算使用了同样的 framework，但还是会有多份的框架被分别签名，打包和加载，因此苹果又把这种 Framework 称为 Embedded Framework(可植入性 Framework)。

不过 iOS8 上开放了 App Extension 功能，可以为一个应用创建插件，这样主app和插件之间共享动态库还是可行的。

数量上，苹果公司建议最多使用6个非系统动态库。

然后就是，在上传App Store打包的时候，苹果会对我们的代码进行一次 Code Singing，包括 app 可执行文件和所有Embedded 的动态库，所以如果是动态从服务器更新的动态库，是签名不了的，sandbox验证动态库的签名非法时，就会造成crash。因此应用插件化、软件版本实时模块升级等功能在iOS上无法实现。不过在 in house(企业发布) 包和develop 包中可以使用。

## 三、Mach-O 文件的动态链接 — dyld

### 3.1 dyld2与dyld3

> [dyld](https://developer.apple.com/library/ios/documentation/System/Conceptual/ManPages_iPhoneOS/man3/dyld.3.html) 是 the dynamic link editor 的缩写，它是苹果的*动态链接器*。在系统内核做好程序准备工作之后，交由 dyld 负责余下的工作。

在2017WWDC，Apple推出了Dyld3。在iOS 13系统中，iOS全面采用新的dyld 3以替代之前版本的dyld 2。dyld 3带来了可观的性能提升，减少了APP的启动时间。

Dyld2是从程序开始时才开始执行的，而Dyld3则将Dyld2的一些过程进行了分解。

<img src="/images/compilelink/44.png" alt="44" style="zoom:60%;" />

Dyld3最大的特点是部分进程外的，分为out-of-process，和in-process。即操作系统在当前app进程之外完成了一部分dyld2在进程内的工作。以达到提升app启动性能和增强安全的目的。

out-process会做：

- 分析Mach-O Headers
- 分析以来的动态库
- 查找需要的Rebase和Bind的符号
- 将上面的分析结果写入缓存。

in-process会做：

- 读取缓存的分析结果
- 验证分析结果
- 加载Mach-O文件
- Rebase&Bind
- Initializers

使用了Dyld3后，App的启动速度会进一步提高。

而WWDC2019 苹果宣布针对Dyld3做了以下优化：

- **避免链接无用的framework；**
- **避免在app启动时链接动态库；**
- **硬链接所有依赖项**

### 3.2 dyld的工作机制

在[Mach-O 文件的装载](https://www.jianshu.com/p/bff19e0a80d4)完成，即内核加载器做完相关的工作后，对于需要动态链接(使用了动态库)的可执行文件(大部分可执行文件都是动态链接的)来说，**控制权会转交给链接器，链接器进而接着处理文件头中的其他加载命令**。真正的库加载和符号解析的工作都是通过`LC_LOAD_DYLINKER`加载命令指定的动态链接器在用户态完成的。通常情况下，使用的是 `/usr/lib/dyld` 作为动态链接器，不过这条加载命令可以指定任何程序作为参数。

链接器接管刚创建的进程的控制权，因为内核将进程的入口点设置为链接器的入口点。

> dyld是一个用户态的进程。dyld不属于内核的一部分，而是作为一个单独的开源项目由苹果进行维护的(当然也属于Darwin的一部分) ，点击查看[项目网址](http://www.opensource.apple.com/source/dyld)。从内核的角度看，dyld是一个可插入的组件，可以替换为第三方的链接器。dyld对应的二进制文件有两个，分别是`/usr/lib/dyld`、`/urs/lib/system/libdyld.dylib`，前者`通用二进制格式(FAT)`，filetype为`MH_DYLINKER`，后者是普通的动态链接库格式(Mach-O)。

<img src="/images/compilelink/30.png" style="zoom:80%;" />

从调用堆栈上看dyld、libdyld.dylib的作用：

<img src="/images/compilelink/31.png" style="zoom:90%;" />

前者`dyld`是**一段可执行的程序**，内核将其映射至进程地址空间，将控制权交给它进行执行，递归加载所需的动态库，其中也会将动态链接器的另一种形式的`libdyld.dylib`加载，因为动态链接器dyld其不但在应用的装载阶段起作用，在主程序运行的时候，其充当**一个库**的角色，还提供了`dlopen`、`dlsym`等api，可以让主程序**显式运行时链接**(见下文)。(关于这一点，没有找到明确的文档说明。如果有人有正确的理解，请一定要评论区告诉我一下，感激不尽)

> Linux中，动态链接库的存在形式稍有不同，Linux动态链接器本身是一个共享对象(动态库)，它的路径是/lib/ld-linux.so.2，这实际上是个软链接，它指向/lib/ld-x.y.z.so， 这个才是真正的动态连接器文件。共享对象其实也是ELF文件，它也有跟可执行文件一样的ELF文件头（包括e_entry、段表等）。动态链接器是个非常特殊的共享对象，它不仅是个共享对象，还是个可执行的程序，可以直接在命令行下面运行。因为ld.so是共享对象，又是动态链接器，所以本来应由动态链接器进行的共享对象的重定位，就要靠自己来，又称“自举”。自举完成后ld.so以一个共享对象的角色，来实现动态链接库的功能。

我们需要了解一下`LC_LOAD_DYLIB`这个加载命令，这个命令会告诉链接器在哪里可以找到这些符号，即动态库的相关信息(ID、时间戳、版本号、兼容版本号等)。

```c
struct dylib {
    union lc_str name;              /* library's path name */
    uint32_t timestamp;             /* library's build time stamp */
    uint32_t current_version;       /* library's current version number */
    uint32_t compatibility_version; /* library's compatibility vers number */
};

struct dylib_command {
    uint32_t cmd;         /* LC_ID_DYLIB, LC_LOAD_{,WEAK_}DYLIB, LC_REEXPORT_DYLIB */
    uint32_t cmdsize;     /* includes pathname string */
    struct dylib dylib;   /* the library identification */
};
```

链接器要加载每一个指定的库，并且搜寻匹配的符号。每个被链接的库(Mach-O格式)都有一个符号表，符号表将符号名称和地址关联起来。符号表在Mach-O目标文件中的地址可以通过`LC_SYMTAB`加载命令指定的 symoff 找到。对应的符号名称在 stroff， 总共有 nsyms 条符号信息。

下面是`LC_SYMTAB`的load_command：

```c
//定义在<mach-o/loader.h>中
struct symtab_command {
    uint32_t	cmd;		/* 加载命令的前两个参数都是cmd和cmdsize，cmd为加载命令的类型，符号表对应的值为LC_SYMTAB */
    uint32_t	cmdsize;	/* symtab_command结构体的大小 */
    uint32_t	symoff;		/* 符号表在文件中的偏移（位置） */
    uint32_t	nsyms;		/* 符号表入口的个数 */
    uint32_t	stroff;		/* 字符串表在文件中的偏移(位置) */
    uint32_t	strsize;	/* 字符串表的大小(字节数) */
};
```

在 <mach-o/dyld.h> 动态库头文件中，也为我们提供了查询所有动态库 image 的方法(也可以使用`otool -L 文件路径`命令来查看，但看着没代码全)：
```c
#include <mach-o/dyld.h>
#include <stdio.h>

void listImages(){
    uint32_t i;
    uint32_t ic = _dyld_image_count();

    printf("Got %d images\n", ic);
    for (i = 0; i < ic; ++ i) {
        printf("%d: %p\t%s\t(slide: %p)\n",
               i,
               _dyld_get_image_header(i),
               _dyld_get_image_name(i),
               _dyld_get_image_vmaddr_slide(i));
    }
}

listImages();  //调用方法

log: 
  ...
  45: 0x1ab331000	/usr/lib/libobjc.A.dylib	(slide: 0x2b1b8000)
  46: 0x1e1767000	/usr/lib/libSystem.B.dylib	(slide: 0x2b1b8000)
  ...
  70: 0x107220000	/usr/lib/system/introspection/libdispatch.dylib	(slide: 0x107220000)
  71: 0x1ab412000	/usr/lib/system/libdyld.dylib	(slide: 0x2b1b8000)
  ...
```

## 四、dyld工作流程详解
通过源码来看一下dyld的工作流程，只是部分片段，详细的可以下载源码。

### 4.1 __dyld_start
下面的汇编代码很简单，如果不清楚，可以看一下这篇汇编入门文章[iOS需要了解的ARM64汇编](https://www.jianshu.com/p/23a9110cff96)。
```arm
#if __arm64__
	.text
	.align 2
	.globl __dyld_start
__dyld_start:
; 操作fp栈帧寄存器，sp栈指针寄存器，配置函数栈帧
	mov 	x28, sp
	and     sp, x28, #~15		// force 16-byte alignment of stack
	mov	x0, #0
	mov	x1, #0
	stp	x1, x0, [sp, #-16]!	// make aligned terminating frame
	mov	fp, sp			// set up fp to point to terminating frame
	sub	sp, sp, #16             // make room for local variables
; L(long 64位) P(point)，在前面的汇编一文中，我们已经知道：r0 - r30 是31个通用整形寄存器。每个寄存器可以存取一个64位大小的数。 
; 当使用 x0 - x30访问时，它就是一个64位的数。
; 当使用 w0 - w30访问时，访问的是这些寄存器的低32位
#if __LP64__       
	ldr     x0, [x28]               // get app's mh into x0
	ldr     x1, [x28, #8]           // get argc into x1 (kernel passes 32-bit int argc as 64-bits on stack to keep alignment)
	add     x2, x28, #16            // get argv into x2
#else
	ldr     w0, [x28]               // get app's mh into x0
	ldr     w1, [x28, #4]           // get argc into x1 (kernel passes 32-bit int argc as 64-bits on stack to keep alignment)
	add     w2, w28, #8             // get argv into x2
#endif
	adrp	x3,___dso_handle@page
	add 	x3,x3,___dso_handle@pageoff // get dyld's mh in to x4
	mov	x4,sp                   // x5 has &startGlue
; 从上面的汇编代码可以看到，主要是在设置dyldbootstrap::start函数调用栈的配置，在前面的汇编一文中，我们已经知道函数的参数，主要通过x0-x7几个寄存器来传递
; 可以看到函数需要的几个参数app_mh，argc，argv，dyld_mh，&startGlue分别被放置到了x0 x1 x2 x4 x5寄存器上
    ; call dyldbootstrap::start(app_mh, argc, argv, dyld_mh, &startGlue)
	bl	__ZN13dyldbootstrap5startEPKN5dyld311MachOLoadedEiPPKcS3_Pm
	mov	x16,x0                  // save entry point address in x16
```

### 4.2 dyldbootstrap::start()
```c
//  This is code to bootstrap dyld.  This work in normally done for a program by dyld and crt.
//  In dyld we have to do this manually.
//  主要做的是dyld的引导工作，一般这个工作通常由 dyld 和 crt(C运行时库 C Run-Time Libray )来完成。但dyld自身加载的时候，只能由自己来做。
uintptr_t start(const dyld3::MachOLoaded* appsMachHeader, int argc, const char* argv[],
				const dyld3::MachOLoaded* dyldsMachHeader, uintptr_t* startGlue)
{
    // Emit kdebug tracepoint to indicate dyld bootstrap has started <rdar://46878536>
    dyld3::kdebug_trace_dyld_marker(DBG_DYLD_TIMING_BOOTSTRAP_START, 0, 0, 0, 0);
    // 如果有slide，那么需要重定位，必须在使用任何全局变量之前，进行该操作
    rebaseDyld(dyldsMachHeader); 
    // kernel sets up env pointer to be just past end of agv array
    const char** envp = &argv[argc+1];	
    // kernel sets up apple pointer to be just past end of envp array
    const char** apple = envp;
    while(*apple != NULL) { ++apple; }
    ++apple;
    // 为stack canary设置一个随机值
    // stack canary：栈的警惕标志(stack canary)，得名于煤矿里的金丝雀，用于探测该灾难的发生。具体办法是在栈的返回地址的存储位置之前放置一个整形值，该值在装入程序时随机确定。栈缓冲区攻击时从低地址向高地址覆盖栈空间，因此会在覆盖返回地址之前就覆盖了警惕标志。返回返回前会检查该警惕标志是否被篡改。
    __guard_setup(apple);
  #if DYLD_INITIALIZER_SUPPORT
    // 执行 dyld 中所有的C++初始化函数。run all C++ initializers inside dyld
    runDyldInitializers(argc, argv, envp, apple);
  #endif
    // 完成所有引导工作，调用dyld::main(). now that we are done bootstrapping dyld, call dyld's main
    uintptr_t appsSlide = appsMachHeader->getSlide();
    return dyld::_main((macho_header*)appsMachHeader, appsSlide, argc, argv, envp, apple, startGlue);
}
```
### 4.3 dyld::_main()
dyld也是Mach-O文件格式的，文件头中的 filetype 字段为`MH_DYLINKER`，区别与可执行文件的 `MH_EXECUTE`，所以dyld也是有main()函数的(默认名称是mian()，也可以自己修改入口地址的)。

因为这个函数太长，写在一起不好阅读，所以按照流程功能点，自上而下分为一个个代码片段。关键的函数会在代码中注释说明

#### 方法名及说明

```c++
// dyld的入口指针，内核加载dyld，跳转到__dyld_start函数：进行了一些寄存器设置，然后就调用了该函数。Entry point for dyld.  The kernel loads dyld and jumps to __dyld_start which sets up some registers and call this function.
// 返回主程序模块的mian()函数地址，__dyld_start中会跳到该地址。Returns address of main() in target program which __dyld_start jumps to
uintptr_t
_main(const macho_header* mainExecutableMH, uintptr_t mainExecutableSlide, 
		int argc, const char* argv[], const char* envp[], const char* apple[], 
		uintptr_t* startGlue)
{
```
#### 第一步 配置上下文信息，设置运行环境，处理环境变量
```c++
	#pragma mark -- 第一步，设置运行环境
    // Grab the cdHash of the main executable from the environment
	uint8_t mainExecutableCDHashBuffer[20];
	const uint8_t* mainExecutableCDHash = nullptr;
	if ( hexToBytes(_simple_getenv(apple, "executable_cdhash"), 40, mainExecutableCDHashBuffer) )
		// 获取主程序的hash
		mainExecutableCDHash = mainExecutableCDHashBuffer;

#if !TARGET_OS_SIMULATOR
	// Trace dyld's load
	notifyKernelAboutImage((macho_header*)&__dso_handle, _simple_getenv(apple, "dyld_file"));
	// Trace the main executable's load
	notifyKernelAboutImage(mainExecutableMH, _simple_getenv(apple, "executable_file"));
#endif

	uintptr_t result = 0;
	// 获取主程序的macho_header结构
	sMainExecutableMachHeader = mainExecutableMH;
	// 获取主程序的slide值
	sMainExecutableSlide = mainExecutableSlide;
    ......
	CRSetCrashLogMessage("dyld: launch started");
	// 传入Mach-O头部以及一些参数设置上下文信息
	setContext(mainExecutableMH, argc, argv, envp, apple);

	// Pickup the pointer to the exec path.
	// 获取主程序路径
	sExecPath = _simple_getenv(apple, "executable_path");

	// <rdar://problem/13868260> Remove interim apple[0] transition code from dyld
	if (!sExecPath) sExecPath = apple[0];
    ......
	if ( sExecPath[0] != '/' ) {
		// have relative path, use cwd to make absolute
		char cwdbuff[MAXPATHLEN];
	    if ( getcwd(cwdbuff, MAXPATHLEN) != NULL ) {
			// maybe use static buffer to avoid calling malloc so early...
			char* s = new char[strlen(cwdbuff) + strlen(sExecPath) + 2];
			strcpy(s, cwdbuff);
			strcat(s, "/");
			strcat(s, sExecPath);
			sExecPath = s;
		}
	}

	// Remember short name of process for later logging
	// 获取进程名称
	sExecShortName = ::strrchr(sExecPath, '/');
	if ( sExecShortName != NULL )
		++sExecShortName;
	else
		sExecShortName = sExecPath;

	// 配置进程受限模式
    configureProcessRestrictions(mainExecutableMH, envp);
    ......
	// 检测环境变量
	checkEnvironmentVariables(envp);
	// 在DYLD_FALLBACK为空时设置默认值
	defaultUninitializedFallbackPaths(envp);
    ......
	// 如果设置了DYLD_PRINT_OPTS则调用printOptions()打印参数
	if ( sEnv.DYLD_PRINT_OPTS )
		printOptions(argv);
	// 如果设置了DYLD_PRINT_ENV则调用printEnvironmentVariables()打印环境变量
	if ( sEnv.DYLD_PRINT_ENV ) 
		printEnvironmentVariables(envp);
    ......
	// 获取当前程序架构
	getHostInfo(mainExecutableMH, mainExecutableSlide);
```
#### 第二步 加载共享缓存
在iOS系统中，UIKit，Foundation等基础库是每个程序都依赖的，需要通过dyld（位于/usr/lib/dyld）一个一个加载到内存，然而如果在每个程序运行的时候都重复的去加载一次，势必造成运行缓慢，为了优化启动速度和提高程序性能，共享缓存机制就应运而生。iOS的dyld采用了一个共享库预链接缓存，苹果从iOS 3.0开始将所有的基础库都移到了这个缓存中，合并成一个大的缓存文件，放到/System/Library/Caches/com.apple.dyld/目录下(OS X中是在/private/var/db/dyld目录)，按不同的架构保存分别保存着，如dyld_shared_cache_armv7。而且在OS X中还有一个辅助的.map文件，而iOS中没有。

如果在iOS上搜索大部分常见的库，比如所有二进制文件都依赖的libSystem，是搜索不到的，这个库的文件不在文件系统中，而是被缓存文件包含。关于如何从共享缓存中提取我们想看的库，可以参考链接[dyld详解第一部分](https://www.dllhook.com/post/238.html#toc_1)


```c++
	#pragma mark -- 第二步，加载共享缓存 // load shared cache
    // 检查共享缓存是否开启，iOS必须开启
	checkSharedRegionDisable((dyld3::MachOLoaded*)mainExecutableMH, mainExecutableSlide);
	if ( gLinkContext.sharedRegionMode != ImageLoader::kDontUseSharedRegion ) {
      /*
       * mapSharedCache加载共享缓存库，其中调用loadDyldCache函数，展开loadDyldCache，有这么几种情况：
         * 仅加载到当前进程mapCachePrivate（模拟器仅支持加载到当前进程）
         * 共享缓存是第一次被加载，就去做加载操作mapCacheSystemWide
         * 共享缓存不是第一次被加载，那么就不做任何处理
       */
	  mapSharedCache();
	}
    ......

	try {
		// add dyld itself to UUID list
		addDyldImageToUUIDList();
```
#### 第三步 实例化主程序image

##### 1. 源码解读

ImageLoader：前面已经提到image(映像文件)常见的有可执行文件、动态链接库。ImageLoader 作用是将这些文件加载进内存，且**每一个文件对应一个ImageLoader实例来负责加载。**

从下面可以看到大概的顺序：先将动态链接的 image 递归加载，再依次进行可执行文件的链接。
```c++
		#pragma mark -- 第三步 实例化主程序，会实例化一个主程序ImageLoader
		// instantiate ImageLoader for main executable
		/*
		 * 展开 instantiateFromLoadedImage 函数, 可以看到主要分三步:
		 * 	isCompatibleMachO()：检查mach-o的subtype是否是当前cpu可以支持；
		 * 	instantiateMainExecutable()： 就是实例化可执行文件，这个期间会解析LoadCommand，这个之后会发送 dyld_image_state_mapped 通知；
		 * 	addImage()： 添加到 allImages中
		 */
		sMainExecutable = instantiateFromLoadedImage(mainExecutableMH, mainExecutableSlide, sExecPath);
		gLinkContext.mainExecutable = sMainExecutable;
		gLinkContext.mainExecutableCodeSigned = hasCodeSignatureLoadCommand(mainExecutableMH);

		// Now that shared cache is loaded, setup an versioned dylib overrides
	#if SUPPORT_VERSIONED_PATHS
		checkVersionedPaths();
	#endif

		// dyld_all_image_infos image list does not contain dyld
		// add it as dyldPath field in dyld_all_image_infos
		// for simulator, dyld_sim is in image list, need host dyld added
#if TARGET_OS_SIMULATOR
		// get path of host dyld from table of syscall vectors in host dyld
		void* addressInDyld = gSyscallHelpers;
#else
		// get path of dyld itself
		void*  addressInDyld = (void*)&__dso_handle;
#endif
		char dyldPathBuffer[MAXPATHLEN+1];
		int len = proc_regionfilename(getpid(), (uint64_t)(long)addressInDyld, dyldPathBuffer, MAXPATHLEN);
		if ( len > 0 ) {
			dyldPathBuffer[len] = '\0'; // proc_regionfilename() does not zero terminate returned string
			if ( strcmp(dyldPathBuffer, gProcessInfo->dyldPath) != 0 )
				gProcessInfo->dyldPath = strdup(dyldPathBuffer);
		}
```
##### 2. instantiateFromLoadedImage

```c++
// The kernel maps in main executable before dyld gets control.  We need to 
// make an ImageLoader* for the already mapped in main executable.
static ImageLoaderMachO* instantiateFromLoadedImage(const macho_header* mh, uintptr_t slide, const char* path)
{
	// try mach-o loader
//	if ( isCompatibleMachO((const uint8_t*)mh, path) ) {
		ImageLoader* image = ImageLoaderMachO::instantiateMainExecutable(mh, slide, path, gLinkContext);
		addImage(image);
		return (ImageLoaderMachO*)image;
//	}
	
//	throw "main executable not a known format";
}
```

从这个方法中，我们大致可以看到加载有三步：

- `isCompatibleMachO` 是检查mach-o的subtype是否是当前cpu可以支持； 
- `instantiateMainExecutable` 就是实例化可执行文件， 这个期间会解析LoadCommand， 这个之后会发送 dyld_image_state_mapped 通知； 
- `addImage` 添加到 allImages中。

#### 第四步 加载插入的动态库

通过遍历 DYLD_INSERT_LIBRARIES 环境变量，调用 loadInsertedDylib 加载。

在三方App的Mach-O文件中通过修改DYLD_INSERT_LIBRARIES的值来加入我们自己的动态库，从而注入代码，hook别人的App。
```c++
		#pragma mark -- 第四步 加载插入的动态库
		// load any inserted libraries
		if	( sEnv.DYLD_INSERT_LIBRARIES != NULL ) {
			for (const char* const* lib = sEnv.DYLD_INSERT_LIBRARIES; *lib != NULL; ++lib) 
				loadInsertedDylib(*lib);
		}
		// record count of inserted libraries so that a flat search will look at 
		// inserted libraries, then main, then others.
		// 记录插入的动态库数量
		sInsertedDylibCount = sAllImages.size()-1;
```
#### 第五步 链接主程序(重点link())

##### 1. 源码解读

```c++
		#pragma mark -- 第五步 链接主程序
		// link main executable
		gLinkContext.linkingMainExecutable = true;
#if SUPPORT_ACCELERATE_TABLES
		if ( mainExcutableAlreadyRebased ) {
			// previous link() on main executable has already adjusted its internal pointers for ASLR 
		    // work around that by rebasing by inverse amount
			sMainExecutable->rebase(gLinkContext, -mainExecutableSlide);
		}
#endif
		/*
        link() 函数的递归调用函数堆栈形式
          ▼ ImageLoader::link() //启动主程序的连接进程   —— ImageLoader.cpp，ImageLoader类中可以发现很多由dyld调用来实现二进制加载逻辑的函数。
            ▼ recursiveLoadLibraries() //进行所有需求动态库的加载
              ▶︎ //确定所有需要的库
              ▼ context.loadLibrary() //来逐个加载。context对象是一个简单的结构体，包含了在方法和函数之间传递的函数指针。这个结构体的loadLibrary成员在libraryLocator()函数（dyld.cpp）中初始化，它完成的功能也只是简单的调用load()函数。
                ▼ load() // 源码在dyld.cpp，会调用各种帮助函数。
                  ▶︎ loadPhase0() → loadPhase1() → ... → loadPhase5() → loadPhase5load() → loadPhase5open() → loadPhase6() 递归调用  //每一个函数都负责加载进程工作的一个具体任务。比如，解析路径或者处理会影响加载进程的环境变量。
                  ▼ loadPhase6() // 该函数从文件系统加载需求的dylib到内存中。然后调用一个ImageLoaderMachO类的实例对象。来完成每个dylib对象Mach-O文件具体的加载和连接逻辑。
         */
		link(sMainExecutable, sEnv.DYLD_BIND_AT_LAUNCH, true, ImageLoader::RPathChain(NULL, NULL), -1);
		sMainExecutable->setNeverUnloadRecursive();
		if ( sMainExecutable->forceFlat() ) {
			gLinkContext.bindFlat = true;
			gLinkContext.prebindUsage = ImageLoader::kUseNoPrebinding;
		}
```
##### 2. ImageLoader::link()

> 加载二进制的过程： instantiate(实例化) –> addImage –> link –> runInitializers 
>
> 其中link就是动态链接的过程

```c++
void ImageLoader::link(const LinkContext& context, bool forceLazysBound, bool preflightOnly, bool neverUnload, const RPathChain& loaderRPaths, const char* imagePath)
{
	//dyld::log("ImageLoader::link(%s) refCount=%d, neverUnload=%d\n", imagePath, fDlopenReferenceCount, fNeverUnload);
	
	// clear error strings
	(*context.setErrorStrings)(0, NULL, NULL, NULL);

	uint64_t t0 = mach_absolute_time();
  // 1. recursiveLoadLibraries 这一步就是根据 LoadCommand 中的 LC_LOAD_DYLIB 把依赖的动态库和Framework加载进来。也就是对这些动态库 instantiate 的过程。 只是动态库不会用instantiateMainExecutable方法来加载了，最终用的是 instantiateFromFile 来加载。
	this->recursiveLoadLibraries(context, preflightOnly, loaderRPaths, imagePath);
	context.notifyBatch(dyld_image_state_dependents_mapped, preflightOnly);

	// we only do the loading step for preflights
	if ( preflightOnly )
		return;

	uint64_t t1 = mach_absolute_time();
	context.clearAllDepths();
  // 2. recursiveUpdateDepth 刷新depth, 就是库依赖的层级。层级越深，depth越大。
  /*
  unsigned int ImageLoader::updateDepth(unsigned int maxDepth)
  {
    STACK_ALLOC_ARRAY(ImageLoader*, danglingUpwards, maxDepth);
    unsigned int depth = this->recursiveUpdateDepth(maxDepth, danglingUpwards);
    for (auto& danglingUpward : danglingUpwards) {
      if ( danglingUpward->fDepth != 0)
        continue;
      danglingUpward->recursiveUpdateDepth(maxDepth, danglingUpwards);
    }
    return depth;
  }
  */
	this->updateDepth(context.imageCount());

	__block uint64_t t2, t3, t4, t5;
	{
		dyld3::ScopedTimer(DBG_DYLD_TIMING_APPLY_FIXUPS, 0, 0, 0);
		t2 = mach_absolute_time();
    // 3. recursiveRebase rebase的过程，recursiveRebase就会把主二进制和依赖进来的动态库全部rebase.
    /*
    void ImageLoader::recursiveRebaseWithAccounting(const LinkContext& context)
    {
      this->recursiveRebase(context);
      vmAccountingSetSuspended(context, false);
    }
     */
		this->recursiveRebaseWithAccounting(context);
		context.notifyBatch(dyld_image_state_rebased, false);

		t3 = mach_absolute_time();
		if ( !context.linkingMainExecutable )
      // 4. 主二进制和依赖进来的动态库全部执行 bind
      /*
      void ImageLoader::recursiveBindWithAccounting(const LinkContext& context, bool forceLazysBound, bool neverUnload)
      {
        this->recursiveBind(context, forceLazysBound, neverUnload, nullptr);
        vmAccountingSetSuspended(context, false);
      }
       */
			this->recursiveBindWithAccounting(context, forceLazysBound, neverUnload);

		t4 = mach_absolute_time();
		if ( !context.linkingMainExecutable )
      // 5. weakBind. 执行weakBind，这里看到如果是主二进制在link的话，是不会在这个时候执行weak bind的，在dyld::_main里面可以看到，是在link完成之后再执行的weakBind.
			this->weakBind(context);
		t5 = mach_absolute_time();
	}

	// interpose any dynamically loaded images
	if ( !context.linkingMainExecutable && (fgInterposingTuples.size() != 0) ) {
		dyld3::ScopedTimer timer(DBG_DYLD_TIMING_APPLY_INTERPOSING, 0, 0, 0);
    // 6. recursiveApplyInterposing. (主二进制link时候也不执行)
		this->recursiveApplyInterposing(context);
	}

	// now that all fixups are done, make __DATA_CONST segments read-only
	if ( !context.linkingMainExecutable )
		this->recursiveMakeDataReadOnly(context);

    if ( !context.linkingMainExecutable )
        context.notifyBatch(dyld_image_state_bound, false);
	uint64_t t6 = mach_absolute_time();

	if ( context.registerDOFs != NULL ) {
		std::vector<DOFInfo> dofs;
		this->recursiveGetDOFSections(context, dofs);
    // 7. registerDOFs. 注册DTrace Object Format。DTrace(Dynamic Trace)是一个提供了 zero disable cost 的动态追踪框架，也就是说当代码中的探针关闭时，不会有额外的资源消耗 - 即使在生产版本中我们也可以将探针留在代码中。只有使用的时候才产生消耗。
    // DTrace 是动态的，也就是说我们可以将它附加在一个已经在运行的程序上，也可以不打断程序将它剥离。不需要重新编译或启动。
		context.registerDOFs(dofs);
	}
	uint64_t t7 = mach_absolute_time();

	// clear error strings
	(*context.setErrorStrings)(0, NULL, NULL, NULL);

	fgTotalLoadLibrariesTime += t1 - t0;
	fgTotalRebaseTime += t3 - t2;
	fgTotalBindTime += t4 - t3;
	fgTotalWeakBindTime += t5 - t4;
	fgTotalDOF += t7 - t6;
	
	// done with initial dylib loads
	fgNextPIEDylibAddress = 0;
}
```

##### 3. 反向依赖

每个库之间的符号并非只能单向依赖。即库与库之间是可以相互依赖符号的。

> 单向依赖：即 A.dylib 依赖 B.dylib。那么B中就不能依赖A中的符号。

> 一次dyld加载进来的二进制之间可以相互依赖符号。

原因很简单，就是因为上面看到动态链接过程中，并不是完全加载完一个被依赖的动态库，再加载下一个的。而是 recursiveLoadLibraies，recursiveRebase，recursiveBind。 所有的单步操作都会等待前一步所有的库完成。因此当 recursiveBind的时候，所有的动态库二进制已经加载进来了，符号就可以互相找了。

一次dyld的过程只会一次动态link，这次link的过程中的库符号可以互相依赖的，但是如果你通过`dlopen`、`-[NSBundle loadBundle]`的方式来延迟加载的动态库就不能反向依赖了，必须单向依赖，因为这是另外一次dyld的过程了。

反向依赖还要有个条件，条件就是符号必须存在，如果因为编译优化把符号给strip了，那就没法bind了，还是会加载失败的。

#### 第六步 链接插入的动态库

```c++
		#pragma mark -- 第六步 链接插入的动态库
		// link any inserted libraries
		// do this after linking main executable so that any dylibs pulled in by inserted 
		// dylibs (e.g. libSystem) will not be in front of dylibs the program uses
		if ( sInsertedDylibCount > 0 ) {
			for(unsigned int i=0; i < sInsertedDylibCount; ++i) {
				ImageLoader* image = sAllImages[i+1];
				link(image, sEnv.DYLD_BIND_AT_LAUNCH, true, ImageLoader::RPathChain(NULL, NULL), -1);
				image->setNeverUnloadRecursive();
			}
			// only INSERTED libraries can interpose
			// register interposing info after all inserted libraries are bound so chaining works
			for(unsigned int i=0; i < sInsertedDylibCount; ++i) {
				ImageLoader* image = sAllImages[i+1];
				image->registerInterposing(gLinkContext);
			}
		}

		// <rdar://problem/19315404> dyld should support interposition even without DYLD_INSERT_LIBRARIES
		for (long i=sInsertedDylibCount+1; i < sAllImages.size(); ++i) {
			ImageLoader* image = sAllImages[i];
			if ( image->inSharedCache() )
				continue;
			image->registerInterposing(gLinkContext);
		}
        ......

		// apply interposing to initial set of images
		for(int i=0; i < sImageRoots.size(); ++i) {
			sImageRoots[i]->applyInterposing(gLinkContext);
		}
		gLinkContext.notifyBatch(dyld_image_state_bound, false);

		// Bind and notify for the inserted images now interposing has been registered
		if ( sInsertedDylibCount > 0 ) {
			for(unsigned int i=0; i < sInsertedDylibCount; ++i) {
				ImageLoader* image = sAllImages[i+1];
				image->recursiveBind(gLinkContext, sEnv.DYLD_BIND_AT_LAUNCH, true);
			}
		}
```
#### 第七步 弱符号绑定weakBind
```		c++
		// <rdar://problem/12186933> do weak binding only after all inserted images linked
		#pragma mark -- 第七步 执行弱符号绑定。weakBind: 从代码中可以看出这一步会对所有含有弱符号的镜像合并排序进行bind。OC中没发现应用场景，可能是C++的吧
		sMainExecutable->weakBind(gLinkContext);
		gLinkContext.linkingMainExecutable = false;

		sMainExecutable->recursiveMakeDataReadOnly(gLinkContext);

		CRSetCrashLogMessage("dyld: launch, running initializers");
        //......
```
#### 第八步 执行初始化方法initialize
##### 1. 源码解读

dyld会优先初始化动态库，然后初始化主程序。

```c++
		#pragma mark -- 第八步 执行初始化方法initialize() 
        // run all initializers
		//attribute((constructor)) 修饰的函数就是在这一步执行的, 即在主程序的main()函数之前。__DATA中有个Section __mod_init_func就是记录这些函数的。
		//与之对应的是attribute((destructor))修饰的函数, 是主程序 main() 执行之后的一些全局函数析构操作, 也是记录在一个Section __mod_term_func中.
		initializeMainExecutable(); 

		// 通知所有的监视进程，本进程要进入main()函数了。 notify any montoring proccesses that this process is about to enter main()
		notifyMonitoringDyldMain();
        //......
```
##### 2. initializeMainExecutable()

调用函数堆栈：

```c++
//先初始化动态库
for(size_t i=1; i < rootCount; ++i) { 
   sImageRoots[i]->runInitializers(gLinkContext, initializerTimes[0]); 
}  // run initialzers for any inserted dylibs
// 再初始化可执行文件 
  // run initializers for main executable and everything it brings up
▼ sMainExecutable->runInitializers() 
  ▼ ImageLoader::processInitializers()
    ▼ ImageLoader::recursiveInitialization()      // 循环遍历images list中所有的imageloader，recursive(递归)初始化。Calling recursive init on all images in images list
      ▼ ImageLoaderMachO::doInitialization()      // 初始化这个image. initialize this image
        ▶︎ ImageLoaderMachO::doImageInit()         // 解析LC_ROUTINES_COMMAND 这个加载命令，可以参考loader.h中该命令的说明，这个命令包含了动态共享库初始化函数的地址，该函数必须在库中任意模块初始化函数(如C++ 静态构造函数等)之前调用
        ▶︎ ImageLoaderMachO::doModInitFunctions()  // 内部会调用C++全局对象的构造函数、__attribute__((constructor))修饰的C函数
        // 以上两个函数中，libSystem相关的都是要首先执行的，而且在上述递归加载动态库过程，libSystem是默认引入的，所以栈中会出现libSystem_initializer的初始化方法
      ▼ context.notifySingle(dyld_image_state_initialized, this, NULL);
        ▶︎ (*sNotifyObjCInit)(image->getRealPath(), image->machHeader());
        // 通知objc, 该image已经完成初始化。objc会调用load_images()
▶︎ (*gLibSystemHelpers->cxa_atexit)(&runAllStaticTerminators, NULL, NULL);// register cxa_atexit() handler to run static terminators in all loaded images when this process exits
```

在上面的`doImageInit`、`doModInitFunctions`函数中，会发现都有判断`libSystem`库是否已加载的代码，即**libSystem要首先加载、初始化**。在上文中，我们已经强调了这个库的重要性。之所以在这里又提到，是因为这个库也起到了将dyld与objc关联起来的作用：

<img src="/images/compilelink/32.png" style="zoom:80%;" />

##### 2. dyld到objc的流程(详细见下篇)

可以从上面的调用堆栈中看到，从dyld到objc的流程：

1. `libSystem` 库的初始化

2. `libdispatch` 库的初始化：`libdispatch` 是实现 GCD 的核心用户空间库。在 `void libdispatch_init(void)` 方法中会调用 `void _os_object_init(void)`

```c++
#if __has_include(<objc/objc-internal.h>)
#include <objc/objc-internal.h>
#else                                  // __asm__ 使函数调用编译为“调用_objc_retain”
extern id _Nullable objc_retain(id _Nullable obj) __asm__("_objc_retain");
extern void objc_release(id _Nullable obj) __asm__("_objc_release");
extern void _objc_init(void);
extern void _objc_atfork_prepare(void);
extern void _objc_atfork_parent(void);
extern void _objc_atfork_child(void);
#endif // __has_include(<objc/objc-internal.h>)

static void*_os_objc_destructInstance(id obj) {
    // noop if only Libystem is loaded
    return obj;
}

void _os_object_init(void) {
    _objc_init();
    Block_callbacks_RR callbacks = {
        sizeof(Block_callbacks_RR),
        (void (*)(const void *))&objc_retain,
        (void (*)(const void *))&objc_release,
        (void (*)(const void *))&_os_objc_destructInstance
    };
    _Block_use_RR2(&callbacks);
#if DISPATCH_COCOA_COMPAT
    const char *v = getenv("OBJC_DEBUG_MISSING_POOLS");
    if (v) _os_object_debug_missing_pools = _dispatch_parse_bool(v);
    v = getenv("DISPATCH_DEBUG_MISSING_POOLS");
    if (v) _os_object_debug_missing_pools = _dispatch_parse_bool(v);
    v = getenv("LIBDISPATCH_DEBUG_MISSING_POOLS");
    if (v) _os_object_debug_missing_pools = _dispatch_parse_bool(v);
#endif
}
```


3. 然后就是 [objc的源码](https://opensource.apple.com/tarballs/objc4/) `objc-os.mm`中的 `_object_init` 函数了：

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
		
    // 注册dyld事件的监听，监听每个image(动态库、可执行文件)的加载，该方法是dyld提供的，内部调用了dyld::registerObjCNotifiers这个方法，记录了这三个分别对应map，init，unmap事件的回调函数。会在相应时机触发
    _dyld_objc_notify_register(&map_images, load_images, unmap_image);

  	// runtime 监听到dyld中image加载后，调用 map_images 做解析和处理，至此，可执行文件中和动态库所有的符号（Class，Protocol，Selector，IMP，…）都已经按格式成功加载到内存中，被 runtime 所管理，在这之后，runtime 的那些方法（动态添加 Class、swizzle 等等才能生效）
    // 接下来 load_images 中调用 call_load_methods 方法，遍历所有加载进来的 Class，按继承层级依次调用 Class 的 +load 方法和其 Category 的 +load 方法

#if __OBJC2__
    didCallDyldNotifyRegister = true;
#endif
}
```
`_dyld_objc_notify_register` 这个方法在苹果开源的dyld里面可以找到，然后看到调用了`dyld::registerObjCNotifiers`这个方法：

```c++
void registerObjCNotifiers(_dyld_objc_notify_mapped mapped, _dyld_objc_notify_init init, _dyld_objc_notify_unmapped unmapped)
{
  // record functions to call
  sNotifyObjCMapped   = mapped;
  sNotifyObjCInit     = init;
  sNotifyObjCUnmapped = unmapped;

  // call 'mapped' function with all images mapped so far
       // 第一次先触发一次ObjCMapped
  try {
      notifyBatchPartial(dyld_image_state_bound, true, NULL, false, true); //内部会触发sNotifyObjCMapped的调用
  }
  catch (const char* msg) {
      // ignore request to abort during registration
  }
}

// 从字面意思可以明白，传进来的分别是 map, init, unmap事件的回调。 dyld的事件通知有以下几种，分别会在特定的时机发送：(注意：map、init、unmap对应到下面枚举中的名称并不一致)

enum dyld_image_states
{
  dyld_image_state_mapped                 = 10,       // No batch notification for this
  dyld_image_state_dependents_mapped      = 20,       // Only batch notification for this
  dyld_image_state_rebased                = 30, 
  dyld_image_state_bound                  = 40,
  dyld_image_state_dependents_initialized = 45,       // Only single notification for this
  dyld_image_state_initialized            = 50,
  dyld_image_state_terminated             = 60        // Only single notification for this
};
```

这三个函数就很熟悉了，位于`objc-runtime-new.mm`中，objc运行时老生常谈的几个方法(关于OBJC的部分，内容太多，这里简单介绍，下篇细谈)，每次有新的镜像加载时都会在指定时机触发这几个方法：

- map_images : 每当 dyld 将一个 image 加载进内存时 , 会触发该函数进行image的一些处理：如果是首次，初始化执行环境等，之后`_read_images`进行读取，进行类、元类、方法、协议、分类的一些加载。
- load_images : 每当 dyld 初始化一个 image 会触发该方法，会对该 image 进行+load的调用
- unmap_image : 每当 dyld 将一个 image 移除时 , 会触发该函数

<img src="/images/compilelink/33.png" style="zoom:75%;" />

值得说明的是，这个初始化的过程远比写出来的要复杂，这里只提到了 runtime 这个分支，还有像 GCD、XPC 等重头的系统库初始化分支没有提及（当然，有缓存机制在，也不会重复初始化），总结起来就是 main 函数执行之前，系统做了非常多的加载和初始化工作，但都被很好的隐藏了，我们无需关心。

然后，从上面最后的代码(*gLibSystemHelpers->cxa_atexit)(&runAllStaticTerminators, NULL, NULL); 以及注释`register cxa_atexit() handler to run static terminators in all loaded images when this process exits`可以看出注册了`cxa_atexit()`函数，当此进程退出时，该处理程序会运行所有加载的image中的静态终止程序(static terminators)。

#### 第九步 查找主程序入口点并返回，__dyld_start会跳转进入
```c++
	    #pragma mark -- 第九步 查找入口点 main() 并返回，调用 getEntryFromLC_MAIN，从 Load Command 读取LC_MAIN入口，如果没有LC_MAIN入口，就读取LC_UNIXTHREAD，然后跳到主程序的入口处执行
	    // find entry point for main executable
		result = (uintptr_t)sMainExecutable->getEntryFromLC_MAIN();
		if ( result != 0 ) {
			// main executable uses LC_MAIN, we need to use helper in libdyld to call into main()
			if ( (gLibSystemHelpers != NULL) && (gLibSystemHelpers->version >= 9) )
				*startGlue = (uintptr_t)gLibSystemHelpers->startGlueToCallExit;
			else
				halt("libdyld.dylib support not present for LC_MAIN");
		}
		else {
			// main executable uses LC_UNIXTHREAD, dyld needs to let "start" in program set up for main()
			result = (uintptr_t)sMainExecutable->getEntryFromLC_UNIXTHREAD();
			*startGlue = 0;
		}
    ......

	catch(const char* message) {
		syncAllImages();
		halt(message);
	}
	catch(...) {
		dyld::log("dyld: launch failed\n");
	}
    ......
	return result;
}
```

### 4.4 小结

引自[iOS 程序 main 函数之前发生了什么](http://blog.sunnyxx.com/2014/08/30/objc-pre-main/)一文中的片段，[《 Mike Ash 这篇 blog 》](https://www.mikeash.com/pyblog/friday-qa-2012-11-09-dyld-dynamic-linking-on-os-x.html)对 dyld 作用顺序的概括：

1.  从 kernel 留下的原始调用栈引导和启动自己
2.  将程序依赖的动态链接库**递归**加载进内存，当然这里有**缓存机制**
3.  non-lazy 符号立即 link 到可执行文件，lazy 的存表里
4.  Runs static initializers for the executable
5.  找到可执行文件的 main 函数，准备参数并调用
6.  程序执行中负责绑定 lazy 符号、提供 runtime dynamic loading services、提供调试器接口
7.  程序main函数 return 后执行 static terminator
8.  某些场景下 main 函数结束后调 libSystem 的 **_exit** 函数


然后，使用调用堆栈，来看下dyld的工作流程，只注释了认为重要的部分。

```C++
#pragma mark -- 内核XNU加载Mach-O
#pragma mark -- 从 XNU内核态 将控制权转移到 dyld用户态
▼ dyld
  ▼ __dyld_start   // 源码在dyldStartup.s这个文件，用汇编实现
    ▼ dyldbootstrap::start()   //dyldInitialization.cpp，负责dyld的引导工作
      ▼ dyld::_main()   // dyld.cpp
	    ▶︎ // 第一步，设置运行环境
	    ▶︎ // 第二步，加载共享缓存
	    ▶︎ // 第三步 实例化主程序，会实例化一个主程序ImageLoader
	    ▼ instantiateFromLoadedImage()  
  	      ▶︎ isCompatibleMachO()  // 检查mach-o的subtype是否是当前cpu可以支持；
  	      ▶︎ instantiateMainExecutable()  // 实例化可执行文件，这个期间会解析LoadCommand，这个之后会发送 dyld_image_state_mapped 通知；
  	      ▶︎ addImage()  // 将可执行文件这个image，添加到 allImages中
	    ▶︎ // 第四步，循环调用该函数，加载插入的动态库
	    ▶︎ loadInsertedDylib()  
	    ▶︎ // 第五步，调用link()函数，链接主程序
	    ▼ link()  
		  ▼ ImageLoader::link() //启动主程序的连接进程   —— ImageLoader.cpp，ImageLoader类中可以发现很多由dyld调用来实现二进制加载逻辑的函数。
			▼ recursiveLoadLibraries() //进行所有需求动态库的加载
			  ▶︎ //确定所有需要的库
			  ▼ context.loadLibrary() //来逐个加载。context对象是一个简单的结构体，包含了在方法和函数之间传递的函数指针。这个结构体的loadLibrary成员在libraryLocator()函数（dyld.cpp）中初始化，它完成的功能也只是简单的调用load()函数。
			    ▼ load() // 源码在dyld.cpp，会调用各种帮助函数。
			      ▶︎ loadPhase0() → loadPhase1() → ... → loadPhase5() → loadPhase5load() → loadPhase5open() → loadPhase6() 递归调用  //每一个函数都负责加载进程工作的一个具体任务。比如，解析路径或者处理会影响加载进程的环境变量。
			      ▼ loadPhase6() // 该函数从文件系统加载需求的dylib到内存中。然后调用一个ImageLoaderMachO类的实例对象。来完成每个dylib对象Mach-O文件具体的加载和连接逻辑。
	    ▶︎ // 第六步，调用link()函数，链接插入的动态库
	    ▶︎ // 第七步，对主程序进行弱符号绑定weakBind
	    ▶︎ sMainExecutable->weakBind(gLinkContext);
	    ▶︎ // 第八步，执行初始化方法 initialize。attribute((constructor)) 修饰的函数就是在这一步执行的, 即在主程序的main()函数之前。__DATA中有个Section __mod_init_func就是记录这些函数的。
	    ▼ initializeMainExecutable()  // dyld会优先初始化动态库，然后初始化主程序。
          ▼ sMainExecutable->runInitializersrunInitializers()  // run initializers for main executable and everything it brings up 
            ▼ ImageLoader::processInitializers()
              ▼ ImageLoader::recursiveInitialization()  // 循环遍历images list中所有的imageloader，recursive(递归)初始化。Calling recursive init on all images in images list
                ▼ ImageLoaderMachO::doInitialization()  // 初始化这个image. initialize this image
                  ▼ ImageLoaderMachO::doImageInit()  //解析LC_ROUTINES_COMMAND 这个加载命令，可以参考loader.h中该命令的说明，这个命令包含了动态共享库初始化函数的地址，该函数必须在库中任意模块初始化函数(如C++ 静态构造函数等)之前调用
                  ▼ ImageLoaderMachO::doModInitFunctions()  // 内部会调用C++全局对象的构造函数、__attribute__((constructor))修饰的C函数
                  // 以上两个函数中，libSystem相关的都是要首先执行的，而且在上述递归加载动态库过程，libSystem是默认引入的，所以栈中会出现libSystem_initializer的初始化方法
          ▶︎ (*gLibSystemHelpers->cxa_atexit)(&runAllStaticTerminators, NULL, NULL);// register cxa_atexit() handler to run static terminators in all loaded images when this process exits
	    ▶︎ // 第九步，查找入口点 main() 并返回，调用 getEntryFromLC_MAIN，从 Load Command 读取LC_MAIN入口，如果没有LC_MAIN入口，就读取LC_UNIXTHREAD，然后跳到主程序的入口处执行
        ▶︎ (uintptr_t)sMainExecutable->getEntryFromLC_MAIN();
```

<img src="/images/compilelink/34.png" style="zoom:80%;" />

关于更多的理论知识，可以阅读下[iOS程序员的自我修养-MachO文件动态链接（四）](https://juejin.im/post/6844903922654511112#heading-23)、[实践篇—fishhook原理](https://juejin.im/post/6844903926051897358)(：程序运行期间通过修改符号表(nl_symbol_ptr和la_symbol_ptr)，来替换要hook的符号对应的地址)，将《程序员的自我修养》中的理论结合iOS系统中的实现机制做了个对比介绍。

## 五、加载动态库方式二: dlopen

> 加载动态库的另一种方式：显式运行时链接dlopen

上面的这种动态链接，其实还可以称为**装载时链接**，与静态链接相比，其实都是属于在程序运行之前进行的链接。还有另一种动态链接称为**显式运行时链接**(**Explicit Runtime Linking**)。

装载时链接：是在程序开始运行时(前)**通过dyld动态加载**。通过dyld加载的动态库需要在编译时进行链接，链接时会做标记，绑定的地址在加载后再决定。

显式运行时链接：即在运行时**通过动态链接器dyld提供的API dlopen 和 dlsym 来加载**。这种方式，在编译时是不需要参与链接的。

- dlopen会把共享库载入运行进程的地址空间，载入的共享库也会有未定义的符号，这样会触发更多的共享库被载入。
- dlopen也可以选择是立刻解析所有引用还是滞后去做。
- dlopen打开动态库后返回的是模块的指针(句柄/文件描述符(FD))
- dlsym的作用就是通过dlopen返回的动态库指针和函数的符号，得到函数的地址然后使用。

**不过，通过这种运行时加载远程动态库的 App，苹果公司是不允许上线 App Store 的，所以只能用于线下调试环节。**

## 六、参考链接
- [《深入理解Mach OS X & iOS 操作系统》]()
- [MachO文件详解--逆向开发](https://www.cnblogs.com/guohai-stronger/p/11915571.html)
- [dyld与ObjC](https://blog.cnbluebox.com/blog/2017/06/20/dyldyu-objc/)
- [Dyld之二: 动态链接过程](https://blog.cnbluebox.com/blog/2017/10/12/dyld2/)
- [dyld详解](https://www.dllhook.com/post/238.html#toc_14)
- [iOS 程序 main 函数之前发生了什么](http://blog.sunnyxx.com/2014/08/30/objc-pre-main/)
- [iOS探索 浅尝辄止dyld加载流程](https://juejin.cn/post/6844904068867948552)

