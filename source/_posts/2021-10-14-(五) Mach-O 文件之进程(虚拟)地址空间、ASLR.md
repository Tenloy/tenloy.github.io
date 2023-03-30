---
title: (五) Mach-O 文件之进程(虚拟)地址空间、ASLR
date: 2021-10-14 04:26:04
urlname: compile-vm-asrl.html
tags:
categories:
  - 编译链接与装载
---

## 一、ASLR引入
进程在自己私有的虚拟地址空间中启动。按照传统方式，进程每一次启动时采用的都是固定的可预见的方式。然而，这意味着某个给定程序在某个给定架构上的进程初始虚拟内存镜像都是基本一致的。而且更严重的问题在于，即使是在进程正常运行的生命周期中，大部分内存分配的操作都是按照同样的方式进行的，因此使得内存中的地址分布具有非常强的可预测性。

尽管这有助于调试，但是也给黑客提供了更大的施展空间。黑客主要采用的方法是代码注入：通过重写内存中的函数指针，黑客就可以将程序的执行路径转到自己的代码，将程序的输入转变为自己的输入。重写内存最常用的方法是采用缓冲区溢出(即利用未经保护的内存复制操作越过上数组的边界)，可参考[缓冲区溢出攻击](https://www.jianshu.com/p/4703ad3efbb9)，将函数的返回地址重写为自己的指针。不仅如此，黑客还有更具创意的技术，例如破坏printf()格式化字符串以及基于堆的缓冲区溢出。此外，任何用户指针甚至结构化的异常处理程序都可以导致代码注入。这里的关键问题在于判断重写哪些指针，也就是说，可靠地判断注入的代码应该在内存中的什么位置。

不论被破解程序的薄弱环节在哪里：缓冲区溢出、格式化字符串攻击或其他方式，黑客都可以花大力气破解一个不安全的程序，找到这个程序的地址空间布局，然后精心设计一种方法，这种方法可以可靠地重现程序中的薄弱环节，并且可以在类似的系统上暴露出一样的薄弱环节。

现在大部分操作系统中都采用了一种称为地址空间布局随机化(ASLR) 的技术，这是一种避免攻击的有效保护。进程每一次启动时，地址空间都会被简单地随机化：**只是偏移，而不是搅乱**。基本的布局(程序文本、数据和库)仍然是一样的。然而，这些部分具体的地址都不同了——区别足够大，可以阻挡黑客对地址的猜测。**实现方法是通过内核将Mach-O的段“平移”某个随机系数**。

## 二、ASLR

地址空间布局随机化(Address Space Layout Randomization，ASLR)是一种针对缓冲区溢出的安全保护技术，通过对堆、栈、共享库映射等线性区布局的随机化，通过增加攻击者预测目的地址的难度，防止攻击者直接定位攻击代码位置，达到阻止溢出攻击的目的的一种技术。iOS4.3开始引入了ASLR技术。

下面分别来看一下，未使用ASLR、使用了ASLR下，进程虚拟地址空间内的分布。下图中左侧是mach-O可执行文件，右侧是链接之后的虚拟地址空间，如果对`__TEXT`、`__DATA`等Segment概念不清楚的地方，可以看一些第二篇关于Mach-O文件结构的介绍。

<img src="/images/compilelink/46.jpg" alt="26" style="zoom:55%;" />

### 2.1 未使用ASLR的虚拟地址空间

- 函数代码存放在__TEXT段中
- 全局变量存放在__DATA段中
- 可执行文件的内存地址是0x0
- 代码段（__TEXT）的内存地址就是LC_SEGMENT(__TEXT)中的VM Address：arm64设备下，为`0x100000000`；非arm64下为`0x4000`
- 可以使用`size -l -m -x`来查看Mach-O的内存分布

<img src="/images/compilelink/26.png" alt="26" style="zoom:55%;" />

### 2.2 使用了ASLR的虚拟地址空间
- LC_SEGMENT(__TEXT)的VM Address为`0x100000000`
- ASLR随机产生的Offset（偏移）为`0x5000`

<img src="/images/compilelink/27.png" alt="26" style="zoom:55%;" />

### 2.3 符号地址计算

> 函数(变量)符号的内存地址、可执行文件地址计算

#### 2.3.1 函数内存地址计算
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

#### 2.3.2 ASLR Offset的获取
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

#### 2.3.3 Symbol Address符号化

- 利用`dwarfdump`可以从dsym文件中得到symbol Address对应的内容：
  + 拿到crash日志后，我们要先确定dsym文件是否匹配。可以使用下面命令查看dsym文件所有架构的UUID：`dwarfdump --uuid CrashDemo.app.dSYM `，然后跟crash日志中Binary Images中的UUID相比对。
  + 用得到的Symbol Address去 dsym 文件中查询，命令如下：`dwarfdump --arch arm64 --lookup [Symbol Address] CrashDemo.app.dSYM`，就可以定位下来具体的代码、函数名、所处的文件、行等信息了

- 如果只是简单的获取符号名，可以用`atos`来符号化：

  ```bash
  atos -o [dsym file path] -l [Load Address] -arch [arch type] [Stack Address]
  ```
  
  + 不需要指定Symbol Address，只需要Load Address、Stack Address即可。

## 三、进程地址空间
由于ASLR的作用，进程的地址空间变得流动性非常大。但是尽管具体的地址会随机“滑动”某个小的偏移量，但整体布局保持不变。

内存空间分为以下几个段：
- **__PAGEZERO**：在32位的系统中，这是内存中单独的一个页面(4KB)，而且这个页面所有的访问权限都被撤消了。在 64 位系统上，这个段对应了一个完整的32位地址空间(即前4GB)。这个段有助于捕捉空指针引用(因为空指针实际上就是 0)，或捕捉将整数当做指针引用(因为32位平台下的 4095 以下的值，以及64位平台下4GB以下的值都在这个范围内)。由于这个范围内所有访问权限(读、写和执行)都被撤消了，所以在这个范围内的任何解引用操作都会引发来自 MMU 的硬件页错误， 进而产生一个内核可以捕捉的陷阱。内核将这个陷阱转换为C++异常或表示总线错误的POSIX信号(SIGBUS) 。

> PAGEZERO不是设计给进程使用的，但是多少成为了恶意代码的温床。想要通过“额外”代码感染Mach-O的攻击者往往发现可以很方便地通过PAGEZERO实现这个目的。PAGEZERO通常不属于目标文件的一部分(其对应的加载指令LC_SEGMENT将filesize指定为0)，但是对此并没有严格的要求.

- **__TEXT**：这个段存放的是程序代码。和其他所有操作系统一样，文本段被设置为r-x，即只读且可执行。这不仅可以防止二进制代码在内存中被修改，还可以通过共享这个只读段优化内存的使用。通过这种方式，同一个程序的多个实例可以仅使用一份TEXT副本。文本段通常包含多个区，实际的代码在_text区中。文本段还可以包含其他只读数据，例如常量和硬编码的字符串。
- **__LINKEDIT**：由dyld使用，这个区包含了字符串表、符号表以及其他数据。
- **__IMPORT**：用于 i386 的二进制文件的导入表。
- **__DATA**：用于可读/可写的数据。
- **__MALLOC_TINY**：用于小于一个页面大小的内存分配。
- **__MALLOC_SMALL**：用于几个页面大小的内存分配。

下面是使用`vmmap(1)`输出的一个实例`程序a`在`32位`硬件设备上运行的进程地址空间，显示了区域的名称、地址范围、权限(当前权限和最高权限)以及映射的名称(通常对应的是Mach-O目标文件，如果有的话)。

32位进程的虚拟地址空间布局：

<img src="/images/compilelink/29.png" alt="26" style="zoom:90%;" />


## 四、小结

应该注意的是，尽管ASLR是很显著的改进，但也不是万能药。黑客仍然能找到聪明的方法破解程序。事实上，目前臭名昭著的“Star 3.0”漏洞就攻破了ASLR，这个漏洞越狱了 iPad 2 上的iOS 4.3。这种破解使用了Retum-Oriented Programming(ROP)攻击技术，通过缓冲区溢出破坏栈，以设置完整的栈帧， 模拟对libSystem的调用。同样的技术也用在iOS 5.0.1的“corona”漏洞中，这个漏洞成功地攻入了所有的苹果设备，包括当时最新的iPhone 4S。

预防攻击的唯一之道就是编写更加安全的代码，并且采用严格的代码审查，既要包含自动的技术，也要有人工的介入。

## 五、参考链接
- 《深入解析Mac OS X & iOS 操作系统》
- [动态调试之ASLR](https://blog.csdn.net/zhongad007/article/details/90022617)
- [iOS crash log 解析](https://blog.csdn.net/xiaofei125145/article/details/50456614)