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
- OS X 和其他 UN\*X 不同，它的库不是“共享对象(.so)”，因为 OS X 和 ELF 不兼容，而且这个概念在 Mach-O 中不存在。OS 中的动态链接文件一般称为**动态库**文件，带有 `.dylib`、`.framework`及链接符号`.tbd`。可以在 `/usr/lib` 目录下找到(这一点和其他所有的 UN*X 一样，不过在OS X 和 iOS 中没有/lib目录)
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

### 2.4 补充两个概念
- `程序模块`：从本质上讲，普通可执行程序和动态库中都包含指令和数据，这一点没有区别。在使用动态库的情况下，程序本身被分为了程序主要模块(`Program1`)和动态链接文件(`Lib.so` `Lib.dylib` `Lib.dll`)，但实际上它们都可以看作是整个程序的一个模块，所以当我们提到程序模块时可以指程序主模块也可以指动态链接库。
- `映像(image)` ，通常也是指这两者。可执行文件/动态链接文件，在装载时被直接映射到进程的虚拟地址空间中运行，它是进程的虚拟空间的映像，所以很多时候，也被叫做映像/镜像文件(Image File)。

### 2.5 .a/.dylib与.framework的区别
前者是纯二进制文件，文件不能直接使用，需要有.h文件的配合(我们在使用系统的.dylib动态库时，经常发现没有头文件，其实这些库的头文件都位于一个已知位置，如`usr/include`(新系统中这个文件夹由SDK附带了，见 [[/usr/include missing on macOS Catalina (with Xcode 11)]](https://apple.stackexchange.com/questions/372032/usr-include-missing-on-macos-catalina-with-xcode-11) )，库文件位于`usr/lib`，使得这些库全局可用)，后者除了二进制文件、头文件还有资源文件，代码可以直接导入使用(`.a + .h + sourceFile = .framework`)。

Framework 是苹果公司的 Cocoa/Cocoa Touch 程序中使用的一种资源打包方式，可以将代码文件、头文件、资源文件（nib/xib、图片、国际化文本）、说明文档等集中在一起，方便开发者使用。**Framework 其实是资源打包的方式，和静态库动态库的本质是没有什么关系(所以framework文件可以是静态库也可以是动态库，iOS 中用到的所有系统 framework 都是动态链接的)**。

在其它大部分平台上，动态库都可以用于不同应用间共享， 共享可执行文件，这就大大节省了内存。但是iOS平台在 iOS 8 之前，苹果不允许第三方框架使用动态方式加载，开发者可以使用的动态 Framework 只有苹果系统提供的 UIKit.Framework，Foundation.Framework 等。开发者要进行模块化，只能打包成静态库文件：`.a + 头文件`、`.framework`(这时候的 Framework 只支持打包成静态库的 Framework)，前种方式打包不够方便，使用时也比较麻烦，没有后者的便捷性。

iOS 8/Xcode 6 推出之后，允许开发者有条件地创建和使用动态库，支持了动态 Framework。开发者打包的动态 Framework 和系统的 UIKit.Framework 还是有很大区别。后者不需要拷贝到目标程序中，是一个链接。而前者在打包和提交 app 时会**被放到 app  main bundle 的根目录中，运行在沙盒里**，而不是系统中。也就是说，不同的 app 就算使用了同样的 framework，但还是会有多份的框架被分别签名，打包和加载，因此苹果又把这种 Framework 称为 Embedded Framework(可植入性 Framework)。

不过 iOS8 上开放了 App Extension 功能，可以为一个应用创建插件，这样主app和插件之间共享动态库还是可行的。

数量上，苹果公司建议最多使用6个非系统动态库。

然后就是，在上传App Store打包的时候，苹果会对我们的代码进行一次 Code Singing，包括 app 可执行文件和所有Embedded 的动态库，所以如果是动态从服务器更新的动态库，是签名不了的，sandbox验证动态库的签名非法时，就会造成crash。因此应用插件化、软件版本实时模块升级等功能在iOS上无法实现。不过在 in house(企业发布) 包和develop 包中可以使用。

## 三、Mach-O 文件的动态链接 — dyld引入

在[Mach-O 文件的装载](https://www.jianshu.com/p/bff19e0a80d4)完成，即内核加载器做完相关的工作后，对于需要动态链接(使用了动态库)的可执行文件(大部分可执行文件都是动态链接的)来说，**控制权会转交给链接器，链接器进而接着处理文件头中的其他加载命令**。真正的库加载和符号解析的工作都是通过`LC_LOAD_DYLINKER`加载命令指定的动态链接器在用户态完成的。通常情况下，使用的是 `/usr/lib/dyld` 作为动态链接器，不过这条加载命令可以指定任何程序作为参数。

链接器接管刚创建的进程的控制权，因为内核将进程的入口点设置为链接器的入口点。

> dyld是一个用户态的进程。dyld不属于内核的一部分，而是作为一个单独的开源项目由苹果进行维护的(当然也属于Darwin的一部分) ，点击查看[项目网址](http://www.opensource.apple.com/source/dyld)。从内核的角度看，dyld是一个可插入的组件，可以替换为第三方的链接器。dyld对应的二进制文件有两个，分别是`/usr/lib/dyld`、`/urs/lib/system/libdyld.dylib`，前者`通用二进制格式(FAT)`，filetype为`MH_DYLINKER`，后者是普通的动态链接库格式(Mach-O)。

<img src="/images/compilelink/30.png" style="zoom:80%;" />

从调用堆栈上看dyld、libdyld.dylib的作用：

<img src="/images/compilelink/31.png" style="zoom:90%;" />

前者`dyld`是**一段可执行的程序**，内核将其映射至进程地址空间，将控制权交给它进行执行，递归加载所需的动态库，其中也会将动态链接器的另一种形式的`libdyld.dylib`加载，因为动态链接器dyld其不但在应用的装载阶段起作用，在主程序运行的时候，其充当**一个库**的角色，还提供了`dlopen`、`dlsym`等api，可以让主程序**显式运行时链接**(见下文)。(关于这一点，没有找到明确的文档说明。如果有人有正确的理解，请一定要评论区告诉我一下，感激不尽)

> Linux中，动态链接库的存在形式稍有不同，Linux动态链接器本身是一个共享对象(动态库)，它的路径是/lib/ld-linux.so.2，这实际上是个软链接，它指向/lib/ld-x.y.z.so， 这个才是真正的动态连接器文件。共享对象其实也是ELF文件，它也有跟可执行文件一样的ELF文件头（包括e_entry、段表等）。动态链接器是个非常特殊的共享对象，它不仅是个共享对象，还是个可执行的程序，可以直接在命令行下面运行。因为ld.so是共享对象，又是动态链接器，所以本来应由动态链接器进行的共享对象的重定位，就要靠自己来，又称“自举”。自举完成后ld.so以一个共享对象的角色，来实现动态链接库的功能。


我们需要了解一下`LC_LOAD_DYLIB`这个加载命令，这个命令会告诉链接器在哪里可以找到这些符号，即动态库的相关信息(ID、时间戳、版本号、兼容版本号等)。链接器要加载每一个指定的库，并且搜寻匹配的符号。每个被链接的库(Mach-O格式)都有一个符号表，符号表将符号名称和地址关联起来。符号表在Mach-O目标文件中的地址可以通过`LC_SYMTAB`加载命令指定的 symoff 找到。对应的符号名称在 stroff， 总共有 nsyms 条符号信息。

下面是`LC_SYMTAB`的load_command：
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
#### 第三步 实例化主程序
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
#### 第五步 链接主程序

实例化之后就是动态链接的过程。link 这个过程就是将加载进来的二进制变为可用状态的过程。简单来说就是：`rebase => binding`
- `rebase`：就是针对 “mach-o在加载到虚拟内存中不是固定的首地址” 这一现象做数据修正的过程。一般可执行文件在没有ASLR造成的首地址不固定的情况下, 装载进虚拟地址中的首地址都是固定的, 比如：Linux下一般都是`0x08040000`，Windows下一般都是`0x0040000`，Mach-O的TEXT地址在__PageZero之后的`0x100000000`地址.
- `binding`：就是将这个二进制调用的外部符号进行绑定的过程。 比如我们objc代码中需要使用到NSObject，即符号`_OBJC_CLASS_$_NSObject`，但是这个符号又不在我们的二进制中，在系统库 Foundation.framework中，因此就需要binding这个操作将对应关系绑定到一起。
- `lazyBinding`：就是在加载动态库的时候不会立即binding, 当时当第一次调用这个方法的时候再实施binding。 做到的方法也很简单： 通过`dyld_stub_binder`这个符号来做。 lazy binding的方法第一次会调用到dyld_stub_binder, 然后dyld_stub_binder负责找到真实的方法，并且将地址bind到桩上，下一次就不用再bind了。
- `weakBinding`：下方还有一步weakBinding

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
#### 第七步 弱符号绑定
```		c++
		// <rdar://problem/12186933> do weak binding only after all inserted images linked
		#pragma mark -- 第七步 执行弱符号绑定。weakBind: 从代码中可以看出这一步会对所有含有弱符号的镜像合并排序进行bind。OC中没发现应用场景，可能是C++的吧
		sMainExecutable->weakBind(gLinkContext);
		gLinkContext.linkingMainExecutable = false;

		sMainExecutable->recursiveMakeDataReadOnly(gLinkContext);

		CRSetCrashLogMessage("dyld: launch, running initializers");
        //......
```
#### 第八步 执行初始化方法
dyld会优先初始化动态库，然后初始化主程序。
```c++
		#pragma mark -- 第八步 执行初始化方法initialize() 
        // run all initializers
		//attribute((constructor)) 修饰的函数就是在这一步执行的, 即在主程序的main()函数之前。__DATA中有个Section __mod_init_func就是记录这些函数的。
		//与之对应的是attribute((destructor))修饰的函数, 是主程序 main() 执行之后的一些全局函数析构操作, 也是记录在一个Section __mod_term_func中.
        /*
        initializeMainExecutable()函数的递归调用函数堆栈形式：
          ▶︎ 先初始化动态库，for(size_t i=1; i < rootCount; ++i) { sImageRoots[i]->runInitializers(gLinkContext, initializerTimes[0]); }  // run initialzers for any inserted dylibs
          ▼ 再初始化可执行文件 sMainExecutable->runInitializers()  // run initializers for main executable and everything it brings up 
            ▼ ImageLoader::processInitializers()
              ▼ ImageLoader::recursiveInitialization()  // 循环遍历images list中所有的imageloader，recursive(递归)初始化。Calling recursive init on all images in images list
                ▼ ImageLoaderMachO::doInitialization()  // 初始化这个image. initialize this image
                  ▼ ImageLoaderMachO::doImageInit()  //解析LC_ROUTINES_COMMAND 这个加载命令，可以参考loader.h中该命令的说明，这个命令包含了动态共享库初始化函数的地址，该函数必须在库中任意模块初始化函数(如C++ 静态构造函数等)之前调用
                  ▼ ImageLoaderMachO::doModInitFunctions()  // 内部会调用C++全局对象的构造函数、__attribute__((constructor))修饰的C函数
                  // 以上两个函数中，libSystem相关的都是要首先执行的，而且在上述递归加载动态库过程，libSystem是默认引入的，所以栈中会出现libSystem_initializer的初始化方法
          ▶︎ (*gLibSystemHelpers->cxa_atexit)(&runAllStaticTerminators, NULL, NULL);// register cxa_atexit() handler to run static terminators in all loaded images when this process exits
        */
		initializeMainExecutable(); 

		// 通知所有的监视进程，本进程要进入main()函数了。 notify any montoring proccesses that this process is about to enter main()
		notifyMonitoringDyldMain();
        //......
```
在上面的`doImageInit`、`doModInitFunctions`函数中，会发现都有判断`libSystem`库是否已加载的代码，即**libSystem要首先加载、初始化**。在上文中，我们已经强调了这个库的重要性。之所以在这里又提到，是因为这个库也起到了将dyld与objc关联起来的作用：

<img src="/images/compilelink/32.png" style="zoom:80%;" />

可以从上面的调用堆栈中看到，从dyld到objc的流程，下面来插一段[objc的源码](https://opensource.apple.com/tarballs/objc4/)`objc-os.mm`中`_object_init`函数的实现：
```c++
void _objc_init(void)
{
    static bool initialized = false;
    if (initialized) return;
    initialized = true;
    
    // 各种初始化
    environ_init();
    tls_init();
    static_init();
    lock_init();
    // 看了一下exception_init是空实现！！就是说objc的异常是完全采用c++那一套的。
    exception_init();
   // 注册dyld事件的监听，该方法是dyld提供的，内部调用了dyld::registerObjCNotifiers这个方法，记录了这三个分别对应map，init，unmap事件的回调函数，会在相应时机触发
    _dyld_objc_notify_register(&map_images, load_images, unmap_image);
}
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


## 五、小结
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

## 六、加载动态库方式二: dlopen

> 加载动态库的另一种方式：显式运行时链接dlopen

上面的这种动态链接，其实还可以称为**装载时链接**，与静态链接相比，其实都是属于在程序运行之前进行的链接。还有另一种动态链接称为**显式运行时链接(Explicit Runtime Linking)**。

装载时链接：是在程序开始运行时(前)**通过dyld动态加载**。通过dyld加载的动态库需要在编译时进行链接，链接时会做标记，绑定的地址在加载后再决定。

显式运行时链接：即在运行时**通过动态链接器dyld提供的API dlopen 和 dlsym 来加载**。这种方式，在编译时是不需要参与链接的。

- dlopen会把共享库载入运行进程的地址空间，载入的共享库也会有未定义的符号，这样会触发更多的共享库被载入。
- dlopen也可以选择是立刻解析所有引用还是滞后去做。
- dlopen打开动态库后返回的是模块的指针(句柄/文件描述符(FD))
- dlsym的作用就是通过dlopen返回的动态库指针和函数的符号，得到函数的地址然后使用。

**不过，通过这种运行时加载远程动态库的 App，苹果公司是不允许上线 App Store 的，所以只能用于线下调试环节。**

## 七、参考链接
- [《深入理解Mach OS X & iOS 操作系统》]()
- [MachO文件详解--逆向开发](https://www.cnblogs.com/guohai-stronger/p/11915571.html)
- [dyld与ObjC](https://blog.cnbluebox.com/blog/2017/06/20/dyldyu-objc/)
- [dyld详解](https://www.dllhook.com/post/238.html#toc_14)
- [iOS 程序 main 函数之前发生了什么](http://blog.sunnyxx.com/2014/08/30/objc-pre-main/)
- [iOS探索 浅尝辄止dyld加载流程](https://juejin.cn/post/6844904068867948552)