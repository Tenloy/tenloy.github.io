---
title: (四) Mach-O 文件的装载、ASLR及符号地址
date: 2021-10-10 04:26:00
urlname: compile-load.html
tags:
categories:
  - 编译链接与装载
---

<img src="/images/compilelink/25.png" alt="25" style="zoom:80%;" />

先附上源码地址：结合 [XNU](https://opensource.apple.com/tarballs/xnu/) 源码(应该不是最新的，且不怎么全，不过用来分析学习也差不多了)，来看加载器的流程，效果更好。重要的两个类：
- `bsd/kern/kern_exec.c`：进程执行的相关操作：线程创建、数据初始化等。
- `bsd/kern/mach_loader.c`：Mach-O文件解析加载相关。第二节中提到的Mach-O文件中的内核加载器负责处理的load command 对应的内核中处理的函数都在该文件中，比如处理`LC_SEGMET`命令的`load_segment`函数、处理`LC_LOAD_DYLINKER`命令的`load_dylinker`函数(负责调用命令指定的动态链接器)。

## 一、装载概述
在链接完成之后，应用开始运行之前，有一段装载过程，我们都知道程序执行时所需要的指令和数据必须在内存中才能够被正常运行。

最简单的办法就是将程序运行所需要的指令和数据全都装入内存中，这样程序就可以顺利运行，这就是最简单的**静态装入**的办法。

但是很多情况下程序所需要的内存数量大于物理内存的数量，当内存的数量不够时，根本的解决办法就是添加内存。相对于磁盘来说，内存是昂贵且稀有的，这种情况自计算机磁盘诞生以来一直如此。所以人们想尽各种办法，希望能够在不添加内存的情况下让更多的程序运行起来，尽可能有效地利用内存。后来研究发现，程序运行时是有**局部性原理**的，所以我们可以将程序最常用的部分驻留在内存中，而将一些不太常用的数据存放在磁盘里面，这就是**动态装入**的基本原理。（这也是**虚拟地址空间**机制要解决的问题，这里不再赘述，大学都学过）

覆盖装入（Overlay）和页映射（Paging）是两种很典型的动态装载方法，它们所采用的思想都差不多，原则上都是利用了程序的局部性原理。动态装入的思想是程序用到哪个模块，就将哪个模块装入内存，如果不用就暂时不装入，存放在磁盘中。

## 二、装载理论篇

在虚拟存储中，现代的硬件MMU都提供地址转换的功能。有了硬件的地址转换和页映射机制，操作系统动态加载可执行文件的方式跟静态加载有了很大的区别。

事实上，从操作系统的角度来看，一个进程最关键的特征是它拥有独立的虚拟地址空间，这使得它有别于其他进程。很多时候一个程序被执行同时都伴随着一个新的进程的创建，那么我们就来看看这种最通常的情形：**创建一个进程，然后装载相应的可执行文件并且执行**。在有虚拟存储的情况下，上述过程最开始只需要做三件事情：
- 创建一个独立的虚拟地址空间。
- 读取可执行文件头，并且建立虚拟空间与可执行文件的映射关系。
- 将CPU的指令寄存器设置成可执行文件的入口地址，启动运行。

**首先是创建虚拟地址空间**。一个虚拟空间由**一组页映射函数**将**虚拟空间的各个页**映射至相应的**物理空间**，所以创建一个虚拟空间实际上并不是创建空间而是**创建映射函数所需要的相应的数据结构**，在i386 的Linux下，创建虚拟地址空间实际上只是分配一个页目录（Page Directory）就可以了，甚至不设置页映射关系，这些映射关系等到后面程序发生页错误的时候再进行设置。

**读取可执行文件头，并且建立虚拟空间与可执行文件的映射关系**。上面那一步的**页映射关系函数是虚拟空间到物理内存的映射关系**，这一步所做的是**虚拟空间与可执行文件的映射关系**。我们知道，当程序执行发生页错误时，操作系统将从物理内存中分配一个物理页，然后将该“缺页”从磁盘中读取到内存中，再设置缺页的虚拟页和物理页的映射关系，这样程序才得以正常运行。

但是很明显的一点是，当操作系统捕获到缺页错误时，它应知道程序当前所需要的页在可执行文件中的哪一个位置。这就是虚拟空间与可执行文件之间的映射关系。从某种角度来看，这一步是整个装载过程中最重要的一步，也是传统意义上“装载”的过程。

> 由于可执行文件在装载时实际上是被映射的虚拟空间，所以可执行文件很多时候又被叫做映像文件（Image）。


很明显，这种映射关系只是保存在操作系统内部的一个数据结构。Linux中将进程虚拟空间中的一个段叫做**虚拟内存区域**（VMA, Virtual Memory Area）；在Windows中将这个叫做**虚拟段**（Virtual Section），其实它们都是同一个概念。

> VMA是一个很重要的概念，它对于我们理解程序的装载执行和操作系统如何管理进程的虚拟空间有非常重要的帮助。

操作系统在内部保存这种结构，很明显是因为当程序执行发生段错误时，它可以**通过查找这样的一个数据结构来定位错误页在可执行文件中的位置**。

**将CPU指令寄存器设置成可执行文件入口，启动运行**。第三步其实也是最简单的一步，操作系统通过设置CPU的指令寄存器将控制权转交给进程，由此进程开始执行。这一步看似简单，实际上在操作系统层面上比较复杂，它涉及内核堆栈和用户堆栈的切换、CPU运行权限的切换。不过从进程的角度看这一步可以简单地认为操作系统执行了一条跳转指令，直接跳转到可执行文件的入口地址(通常是text区的地址)。

- ELF文件头中，有`e_entry`字段保存入口地址
- Mach-O文件中的`LC_MAIN`加载指令作用就是设置程序主程序的入口点地址和栈大小)

## 三、Mach-O文件的装载

[(二) Mach-O 文件结构](https://www.jianshu.com/p/332b183c055a) 介绍 `Mach Heade` 中的 `Load Command` 加载命令，结合其用途，就可以简单看出可执行文件的装载流程：

- 首先，是由内核加载器(定义在`bsd/kern/mach_loader.c`文件中)来处理一些需要由内核加载器直接使用的加载命令。**内核的部分(内核加载器)负责新进程的基本设置——分配虚拟内存，创建主线程，以及处理任何可能的代码签名/加密的工作**。（这也是本篇内容主要讲的）
- 接着，对于需要动态链接(使用了动态库)的可执行文件(大部分可执行文件都是动态链接的)来说，**控制权会转交给链接器，链接器进而接着处理文件头中的其他加载命令**。真正的库加载和符号解析的工作都是通过`LC_LOAD_DYLINKER`命令指定的**动态链接器**在用户态完成的。（下一篇文章再细讲`dyld`及**动态链接**）

下面通过代码来看一下具体的过程。下面通过一个调用栈图来说明， 这里面每个方法都做了很多事情，这里只注释了到_dyld_start的关键操作，很简略。有兴趣可以详细看源码`kern_exec.c`、`mach_loader.c`

```c
▼ execve       // 用户点击了app，用户态会发送一个系统调用 execve 到内核
  ▼ __mac_execve  // 主要是为加载镜像进行数据的初始化，以及资源相关的操作，以及创建线程
    ▼ exec_activate_image // 拷贝可执行文件到内存中，并根据不同的可执行文件类型选择不同的加载函数，所有的镜像的加载要么终止在一个错误上，要么最终完成加载镜像。
      // 在 encapsulated_binary 这一步会根据image的类型选择imgact的方法
      /*
       * 该方法为Mach-o Binary对应的执行方法；
       * 如果image类型为Fat Binary，对应方法为exec_fat_imgact；
       * 如果image类型为Interpreter Script，对应方法为exec_shell_imgact
       */
      ▼ exec_mach_imgact   
        ▶︎ // 首先对Mach-O做检测，会检测Mach-O头部，解析其架构、检查imgp等内容，判断魔数、cputype、cpusubtype等信息。如果image无效，会直接触发assert(exec_failure_reason == OS_REASON_NULL); 退出。
          // 拒绝接受Dylib和Bundle这样的文件，这些文件会由dyld负责加载。然后把Mach-O映射到内存中去，调用load_machfile()
        ▼ load_machfile
          ▶︎ // load_machfile会加载Mach-O中的各种load command命令。在其内部会禁止数据段执行，防止溢出漏洞攻击，还会设置地址空间布局随机化（ASLR），还有一些映射的调整。
            // 真正负责对加载命令解析的是parse_machfile()
          ▼ parse_machfile  //解析主二进制macho
            ▶︎ /* 
               * 首先，对image头中的filetype进行分析，可执行文件MH_EXECUTE不允许被二次加载(depth = 1)；动态链接编辑器MH_DYLINKER必须是被可执行文件加载的(depth = 2)
               * 然后，循环遍历所有的load command，分别调用对应的内核函数进行处理
               *   LC_SEGMET：load_segment函数：对于每一个段，将文件中相应的内容加载到内存中：从偏移量为 fileoff 处加载 filesize 字节到虚拟内存地址 vmaddr 处的 vmsize 字节。每一个段的页面都根据 initprot 进行初始化，initprot 指定了如何通过读/写/执行位初始化页面的保护级别。
               *   LC_UNIXTHREAD：load_unixthread函数，见下文
               *   LC_MAIN：load_main函数
               *   LC_LOAD_DYLINKER：获取动态链接器相关的信息，下面load_dylinker会根据信息，启动动态链接器
               *   LC_CODE_SIGNATURE：load_code_signature函数，进行验证，如果无效会退出。理论部分，回见第二节load_command `LC_CODE_SIGNATURE `部分。
               *   其他的不再多说，有兴趣可以自己看源码
               */
            ▼ load_dylinker // 解析完 macho后，根据macho中的 LC_LOAD_DYLINKER 这个LoadCommand来启动这个二进制的加载器，即 /usr/bin/dyld
              ▼ parse_machfile // 开始解析 dyld 这个mach-o文件
                ▼ load_unixthread // 解析 dyld 的 LC_UNIXTHREAD 命令，这个过程中会解析出entry_point
                  ▼ load_threadentry  // 获取入口地址
                    ▶︎ thread_entrypoint  // 里面只有i386和x86架构的，没有arm的，但是原理是一样的
                  ▶︎ //上一步获取到地址后，会再加上slide，ASLR偏移，到此，就获取到了dyld的入口地址，也就是 _dyld_start 函数的地址
        ▼ activate_exec_state
          ▶︎ thread_setentrypoint // 设置entry_point。直接把entry_point地址写入到用户态的寄存器里面了。
          //这一步开始，_dyld_start就真正开始执行了。

▼ dyld
  ▼ __dyld_start  // 源码在dyldStartup.s这个文件，用汇编实现
    ▼ dyldbootstrap::start() 
      ▼ dyld::_main()
        ▼ //函数的最后，调用 getEntryFromLC_MAIN，从 Load Command 读取LC_MAIN入口，如果没有LC_MAIN入口，就读取LC_UNIXTHREAD，然后跳到主程序的入口处执行
        ▼ 这是下篇内容
```

## 四、ASLR

### 4.1 引入背景

进程在自己私有的虚拟地址空间中启动。按照传统方式，进程每一次启动时采用的都是固定的可预见的方式。然而，这意味着某个给定程序在某个给定架构上的进程初始虚拟内存镜像都是基本一致的。而且更严重的问题在于，即使是在进程正常运行的生命周期中，大部分内存分配的操作都是按照同样的方式进行的，因此使得内存中的地址分布具有非常强的可预测性。

尽管这有助于调试，但是也给黑客提供了更大的施展空间。黑客主要采用的方法是代码注入：通过重写内存中的函数指针，黑客就可以将程序的执行路径转到自己的代码，将程序的输入转变为自己的输入。重写内存最常用的方法是采用缓冲区溢出(即利用未经保护的内存复制操作越过上数组的边界)，可参考[缓冲区溢出攻击](https://www.jianshu.com/p/4703ad3efbb9)，将函数的返回地址重写为自己的指针。不仅如此，黑客还有更具创意的技术，例如破坏printf()格式化字符串以及基于堆的缓冲区溢出。此外，任何用户指针甚至结构化的异常处理程序都可以导致代码注入。这里的关键问题在于判断重写哪些指针，也就是说，可靠地判断注入的代码应该在内存中的什么位置。

不论被破解程序的薄弱环节在哪里：缓冲区溢出、格式化字符串攻击或其他方式，黑客都可以花大力气破解一个不安全的程序，找到这个程序的地址空间布局，然后精心设计一种方法，这种方法可以可靠地重现程序中的薄弱环节，并且可以在类似的系统上暴露出一样的薄弱环节。

现在大部分操作系统中都采用了一种称为地址空间布局随机化(ASLR) 的技术，这是一种避免攻击的有效保护。进程每一次启动时，地址空间都会被简单地随机化：**只是偏移，而不是搅乱**。基本的布局(程序文本、数据和库)仍然是一样的。然而，这些部分具体的地址都不同了——区别足够大，可以阻挡黑客对地址的猜测。**实现方法是通过内核将Mach-O的段“平移”某个随机系数**。

### 4.2 概述

地址空间布局随机化(Address Space Layout Randomization，ASLR)是一种针对缓冲区溢出的安全保护技术，通过对堆、栈、共享库映射等线性区布局的随机化，通过增加攻击者预测目的地址的难度，防止攻击者直接定位攻击代码位置，达到阻止溢出攻击的目的的一种技术。iOS4.3开始引入了ASLR技术。

下面分别来看一下，未使用ASLR、使用了ASLR下，进程虚拟地址空间内的分布。（如果对`__TEXT`、`__DATA`等Segment概念不清楚的地方，可以看一些第二篇关于Mach-O文件结构的介绍）

<img src="/images/compilelink/46.jpg" alt="26" style="zoom:55%;" />

### 4.3 未使用ASLR的虚拟地址空间

下图中左侧是mach-O可执行文件，右侧是链接之后的虚拟地址空间。

- 函数代码存放在__TEXT段中
- 全局变量存放在__DATA段中
- 可执行文件的内存地址是0x0
- 代码段（__TEXT）的内存地址就是LC_SEGMENT(__TEXT)中的VM Address：arm64设备下，为`0x100000000`；非arm64下为`0x4000`
- 可以使用`size -l -m -x`来查看Mach-O的内存分布

<img src="/images/compilelink/26.png" alt="26" style="zoom:55%;" />

### 4.4 使用了ASLR的虚拟地址空间

- LC_SEGMENT(__TEXT)的VM Address为`0x100000000`
- ASLR随机产生的Offset（偏移）为`0x5000`
- 再次强调：由于ASLR的作用，进程的地址空间变得流动性非常大。但是尽管具体的地址会随机“滑动”某个小的偏移量，但整体布局保持不变。

<img src="/images/compilelink/27.png" alt="26" style="zoom:55%;" />

### 4.5 符号地址计算

> 函数(变量)符号的内存地址、可执行文件地址计算

#### 4.5.1 函数内存地址计算

- **File Offset**：在当前架构(MachO)文件中的偏移量。
- **VM Address【未偏移/ASLR偏移前】** ：
  - 编译链接后，映射到虚拟地址中的内存起始地址。 
  - `VM Address = File Offset + __PAGEZERO Size`(__PAGEZERO段在MachO文件中没有实际大小，在VM中展开)
- **Load Address【ASLR偏移后的VM Address】**：
  - 在运行时加载到虚拟内存的起始位置。（真正的运行时地址，也是虚拟地址空间中的地址）。
  - Slide是加载到内存的偏移，这个偏移值是一个随机值，每次运行都不相同。`Load Address = VM Address + Slide(ASLR Offset)`
  - 当未开启ASLR时，Load Address(运行时VM Address) ＝ 上面的静态VM Address

注意：

- MachO文件一生成，代码段、数据段在MachO文件中的位置(File Offset)、在运行内存(虚拟内存)中的地址值(vm address)就已经确定了。
- 运行时，真正的运行内存地址，还得加上ASLR偏移量。
- 开发者面向的地址，都是虚拟内存中的地址（虚拟地址），而不是真实的硬件设备上的地址（物理地址）。

由于dsym符号表是编译时生成的地址，crash堆栈的地址是运行时地址，这个时候需要经过转换才能正确的符号化。crash日志里的符号地址被称为Stack Address，而编译后的符号地址被称为Symbol Address，他们之间的关系如下：`Stack Address = Symbol Address + Slide`。

符号化就是通过Stack Address到dsym文件中寻找对应符号信息的过程。

**Hopper、IDA图形化工具中的地址都是未使用ASLR前的VM Address**。

#### 4.5.2 ASLR Offset的获取

ASLR Offset有的地方也叫做`slide`，获取方法：

- 在运行时由API `dyld_get_image_vmaddr_slide()`，来获取image虚拟地址的偏移量。

```c
//函数原型如下：
extern intptr_t   _dyld_get_image_vmaddr_slide(uint32_t image_index);

//一般使用方法如下：
uint32_t c = _dyld_image_count();
for (uint32_t i = 0; i < c; i++) {
  intptr_t index  = _dyld_get_image_vmaddr_slide(i);
}
```

- 通过`lldb`命令`image list -o -f` 进行获取（本地、远程`debugserver`调试都可以），如下图：

  <img src="/images/compilelink/28.png" alt="26" style="zoom:80%;" />

- 根据运行时crash中的 `binary image`信息 和 ELF 文件的 `load command` 计算的到。比如下例：

```c
//下面是crash信息，其中包括了抛出异常的线程的函数调用栈信息，日志下方有binary image信息，都只摘取了部分：
/*
 第一列，调用顺序
 第二列，对应函数所属的 binary image
 第三列，stack address
 第四列，地址的符号＋偏移的表示法，运算结果等于第三列
*/
Last Exception Backtrace:  
0   CoreFoundation                0x189127100 __exceptionPreprocess + 132  
1   libobjc.A.dylib               0x1959e01fc objc_exception_throw + 60  
2   CoreFoundation                0x189127040 +[NSException raise:format:] + 128  
3   CrashDemo                     0x100a8666c 0x10003c000 + 10790508  
4   libsystem_platform.dylib      0x19614bb0c _sigtramp + 56  
5   CrashDemo                     0x1006ef164 0x10003c000 + 7024996  
6   CrashDemo                     0x1006e8580 0x10003c000 + 6997376  
7   CrashDemo                     0x1006e8014 0x10003c000 + 6995988  
8   CrashDemo                     0x1006e7c94 0x10003c000 + 6995092  
9   CrashDemo                     0x1006f2460 0x10003c000 + 7038048  

/* 
 第一列，虚拟地址空间区块；
 第二列，映射文件名；
 第三列：加载的image的UUID；
 第四列，映射文件路径 
*/
Binary Images:  
0x10003c000 - 0x100f7bfff CrashDemo arm64  <b5ae3570a013386688c7007ee2e73978> /var/mobile/Applications/05C398CE-21E9-43C2-967F-26DD0A327932/CrashDemo.app/CrashDemo  
0x12007c000 - 0x1200a3fff dyld arm64  <628da833271c3f9bb8d44c34060f55e0> /usr/lib/dyld


//下面是使用 otool 工具查看到的 MedicalRecordsFolder（我的程序）的 加载命令 。
$otool -l CrashDemo.app/CrashDemo   
CrashDemo.app/CrashDemo:  
Load command 0  
      cmd LC_SEGMENT_64  
  cmdsize 72  
  segname __PAGEZERO  
   vmaddr 0x0000000000000000  
   vmsize 0x0000000100000000  
  fileoff 0  
 filesize 0  
  maxprot 0x00000000  
 initprot 0x00000000  
   nsects 0  
    flags 0x0  
Load command 1  
      cmd LC_SEGMENT_64  
  cmdsize 792  
  segname __TEXT  
   vmaddr 0x0000000100000000  
   vmsize 0x000000000000c000  
  fileoff 0  
 filesize 49152  
  maxprot 0x00000005  
 initprot 0x00000005  
   nsects 9  
    flags 0x0  
……  
Load command 2 
……  
```

在 binary image 第一行可以看出进程空间的 0x10003c000 - 0x100f7bfff 这个区域在运行时被映射为 CrashDemo 内的内容，也就是我们的 ELF 文件(区域起始地址为0x10003c000)。
而在 Load Command 中看到的`__TEXT`的段起始地址却是 0x0000000100000000。
显而易见：slide = 0x10003c000(Load Address) - 0x100000000(VM Address) = 0x3c000；之后，就可以通过公式`symbol address = stack address - slide;` 来计算stack address 在crash log 中已经找到了。

#### 4.5.3 Symbol Address符号化

- 利用`dwarfdump`可以从dsym文件中得到symbol Address对应的内容：

  + 拿到crash日志后，我们要先确定dsym文件是否匹配。可以使用下面命令查看dsym文件所有架构的UUID：`dwarfdump --uuid CrashDemo.app.dSYM `，然后跟crash日志中Binary Images中的UUID相比对。
  + 用得到的Symbol Address去 dsym 文件中查询，命令如下：`dwarfdump --arch arm64 --lookup [Symbol Address] CrashDemo.app.dSYM`，就可以定位下来具体的代码、函数名、所处的文件、行等信息了

- 如果只是简单的获取符号名，可以用`atos`来符号化：

  ```bash
  atos -o [dsym file path] -l [模块的Load Address] -arch [arch type] [Stack Address]
  # 比如：5   CrashDemo              0x1006ef164       0x10003c000 + 7024996
  #                               【stack address】  【模块的加载地址】
  ```

  + 不需要指定Symbol Address，只需要模块的Load Address、Stack Address即可。

### 4.6 小结

应该注意的是，尽管ASLR是很显著的改进，但也不是万能药。黑客仍然能找到聪明的方法破解程序。事实上，目前臭名昭著的“Star 3.0”漏洞就攻破了ASLR，这个漏洞越狱了 iPad 2 上的iOS 4.3。这种破解使用了Retum-Oriented Programming(ROP)攻击技术，通过缓冲区溢出破坏栈，以设置完整的栈帧， 模拟对libSystem的调用。同样的技术也用在iOS 5.0.1的“corona”漏洞中，这个漏洞成功地攻入了所有的苹果设备，包括当时最新的iPhone 4S。

预防攻击的唯一之道就是编写更加安全的代码，并且采用严格的代码审查，既要包含自动的技术，也要有人工的介入。

### 4.7 参考链接

- 《深入解析Mac OS X & iOS 操作系统》
- [动态调试之ASLR](https://blog.csdn.net/zhongad007/article/details/90022617)
- [iOS crash log 解析](https://blog.csdn.net/xiaofei125145/article/details/50456614)

## 五、Linux ELF文件的装载（了解）

首先在用户层面，bash进程会调用fork()系统调用创建一个新的进程，然后新的进程调用 `execve()`系统调用执行指定的ELF文件，原先的bash进程继续返回等待刚才启动的新进程结束，然后继续等待用户输入命令。 execve() 系统调用被定义在unistd.h，它的原型如下：
```c
/*
 * 三个参数分别是被执行的程序文件名、执行参数和环境变量。
 */
int execve(const char *filename, char *const argv[], char *const envp[]); 
```

Glibc对该系统调用进行了包装，提供了 execl()、execlp()、execle()、execv()、execvp()等5个不同形式的exec系列API，它们只是在调用的参数形式上有所区别，但最终都会调用到 execve() 这个系统中。

在进入 execve() 系统调用之后，Linux内核就开始进行真正的装载工作。

- `sys_execve()`，在内核中，该函数是execve()系统调用相应的入口，定义在arch\i386\kernel\Process.c。 该函数进行一些参数的检查复制之后，调用 do_execve()。
- `do_execve()`，该函数会首先查找被执行的文件，如果找到文件，则读取文件的前128个字节。目的是判断文件的格式，每种可执行文件的格式的开头几个字节都是很特殊的，特别是开头4个字节，常常被称做**魔数**（Magic Number），通过对魔数的判断可以确定文件的格式和类型。比如：
  + ELF的可执行文件格式的头4个字节为0x7F、’e’、’l’、’f’；
  + Java的可执行文件格式的头4个字节为’c’、’a’、’f’、’e’；
  + 如果被执行的是Shell脚本或perl、python等这种解释型语言的脚本，那么它的第一行往往是 `#!/bin/sh` 或 `#!/usr/bin/perl` 或 `#!/usr/bin/python` ，这时候前两个字节 `#` 和 `!` 就构成了魔数，系统一旦判断到这两个字节，就对后面的字符串进行解析，以确定具体的解释程序的路径。
  + 当do_execve()读取了这128个字节的文件头部之后，然后调用search_binary_handle()。
- `search_binary_handle()`，该函数会去搜索和匹配合适的可执行文件装载处理过程。**Linux中所有被支持的可执行文件格式都有相应的装载处理过程**，此函数会通过判断文件头部的魔数确定文件的格式，并且调用相应的装载处理过程。比如：
  + ELF可执行文件的装载处理过程叫做 load_elf_binary()； 
  + a.out可执行文件的装载处理过程叫做 load_aout_binary()；
  + 装载可执行脚本程序的处理过程叫做 load_script()。
- `load_elf_binary()`，这个函数被定义在fs/Binfmt_elf.c，代码比较长，它的主要步骤是：
  1. 检查ELF可执行文件格式的有效性，比如魔数、程序头表中段（Segment）的数量。
  2. 寻找动态链接的 `.interp` 段，设置动态链接器路径。
  3. 根据ELF可执行文件的程序头表的描述，对ELF文件进行映射，比如代码、数据、只读数据。
  4. 初始化ELF进程环境，比如进程启动时EDX寄存器的地址应该是 DT_FINI 的地址（动态链接相关）。
  5. 将系统调用的返回地址修改成ELF可执行文件的入口点，这个入口点取决于程序的链接方式，对于静态链接的ELF可执行文件，这个程序入口就是ELF文件的文件头中 `e_entry` 所指的地址；对于动态链接的ELF可执行文件，程序入口点是动态链接器。

当 load_elf_binary() 执行完毕，返回至 do_execve() 再返回至 sys_execve() 时， 上面的第5步中已经把系统调用的返回地址改成了被装载的ELF程序(或动态链接器)的入口地址了。所以当 `sys_execve()`系统调用从内核态返回到用户态时，EIP 寄存器直接跳转到了ELF程序的入口地址，于是新的程序开始执行，ELF可执行文件装载完成。

## 五、参考链接

- [《深入理解Mach OS X & iOS 操作系统》]()
- [《程序员的自我修养》]()
- [Dyld系列之一：_dyld_start之前](https://blog.cnbluebox.com/blog/2017/06/30/dyld2/)