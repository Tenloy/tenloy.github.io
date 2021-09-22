---
title: (一) Clang/LLVM 介绍、OC 程序的编译过程
date: 2021-09-22 14:25:45
urlname: compile-clang-llvm.html
tags:
categories:
  - 编译链接与装载
---

## 一、编译、链接工具 — Clang/LLVM

> [官网定义：](https://llvm.org/)
>
> - The LLVM Project is a collection of modular and reusable compiler and toolchain technologies(LLVM项目是一系列分模块、可重用的编译**工具链**). Despite its name, LLVM has little to do with traditional virtual machines. The name "LLVM" itself is not an acronym; it is the full name of the project.
> - Clang is an "LLVM native" C/C++/Objective-C compiler. 
>

### 1.1 LLVM的诞生

2000年，伊利诺伊大学厄巴纳－香槟分校（University of Illinois at Urbana-Champaign 简称UIUC）这所享有世界声望的一流公立研究型大学的克里斯·拉特纳(Chris Lattner，twitter为 [clattner_llvm](https://twitter.com/clattner_llvm)） 开发了一个叫作 Low Level Virtual Machine 的编译器开发工具套件，后来涉及范围越来越大，可以用于常规编译器，JIT编译器，汇编器，调试器，静态分析工具等一系列跟编程语言相关的工作，于是就把简称 LLVM 这个简称作为了正式的名字。

2005年，由于GCC 对于 Objective-C 的支持比较差，效率和性能都没有办法达到苹果公司的要求，而且它还难以推动 GCC 团队。于是，苹果公司决定自己来掌握编译相关的工具链，于是将Chris Lattner招入麾下，发起了 Clang 软件项目。
- Clang 作为 LLVM 编译器工具集的前端（front-end），目的是输出代码对应的抽象语法树（Abstract Syntax Tree, AST），并将代码编译成LLVM Bitcode。接着在后端（back-end）使用LLVM编译成平台相关的机器语言。Clang支持C、C++、Objective C。
- 测试证明Clang编译Objective-C代码时速度为GCC的3倍，还能针对用户发生的编译错误准确地给出建议。
- 此后，苹果使用的 GCC 全面替换成了 LLVM。

2010年，Chris Lattner开始主导开发 Swift 语言。这也使得 Swift 这门集各种高级语言特性的语言，能够在非常高的起点上，出现在开发者面前。

2012年，LLVM 获得美国计算机学会 ACM 的软件系统大奖，和 UNIX，WWW，TCP/IP，Tex，JAVA 等齐名。

### 1.2 LLVM及其子项目

#### 1.2.1 概述

llvm特点：

- 模块化
- 统一的中间代码IR，而前端、后端可以不一样。而GCC的前端、后端耦合在了一起，所以支持一门新语言或者新的平台，非常困难。
- 功能强大的Pass系统，根据依赖性自动对Pass（包括分析、转换和代码生成Pass）进行排序，管道化以提高效率。

llvm有广义和狭义两种定义：
- 在广义中，llvm特指一整个编译器框架，**是一个模块化和可重用的编译器和工具链技术的集合**，由前端、优化器、后端组成，clang只是用于c/c++的一种前端，llvm针对不同的语言可以设计不同的前端，同样的针对不同的平台架构（amd，arm，misp），也会有不同后端设计
- 在狭义中 ，特指llvm后端，指优化器（pass）对IR进行一系列优化直到目标代码生成的过程

简单罗列LLVM几个主要的子项目，详见[官网](https://llvm.org/)：
- LLVM Core libraries：LLVM核心库提供了一个独立于源和目标架构的现代[优化器optimizer](https://llvm.org/docs/Passes.html)，以及对许多流行cpu(以及一些不太常见的cpu)的[代码生成(code generation)](https://llvm.org/docs/CodeGenerator.html)支持。这些库是围绕一种被称为LLVM中间表示(“LLVM IR”)的良好指定的代码表示构建的。

- Clang：一个 C/C++/Objective-C 编译器，提供高效快速的编译效率，比 GCC 快3倍，其中的 clang static analyzer 主要是进行语法分析，语义分析和生成中间代码，当然这个过程会对代码进行检查，出错的和需要警告的会标注出来。(见下文详述)

- lld： 是LLVM开发一个内置的，平台独立的链接器，去除对所有第三方链接器的依赖。在2017年5月，lld已经支持ELF、PE/COFF、和Mach-O。在lld支持不完全的情况下，用户可以使用其他项目，如 GNU ld 链接器。 
lld支持链接时优化。当LLVM链接时优化被启用时，LLVM可以输出bitcode而不是本机代码，而本机代码生成由链接器优化处理。

- LLDB：基于 LLVM 和 Clang提供的库构建的一个优秀的本地调试器，使用了 Clang ASTs、表达式解析器、LLVM JIT、LLVM 反汇编器等。

#### 1.2.2 Clang

从[Clang的源码](http://llvm.org/svn/llvm-project/cfe/trunk/lib/)目录中可以大致看出Clang提供的功能：

<img src="/images/compilelink/01.png" alt="01" style="zoom:80%;" />

##### 1. Clang提供了哪些功能？
Clang 为一些需要分析代码语法、语义信息的工具提供了基础设施。分别是：
- **LibClang**。LibClang提供了一个稳定的高级 C 接口，Xcode 使用的就是 LibClang。LibClang 可以访问 Clang 的上层高级抽象的能力，比如获取所有 Token、遍历语法树、代码补全等。由于 API 很稳定，Clang 版本更新对其 影响不大。但是，LibClang 并不能完全访问到 Clang AST 信息。

- **Clang Plugins**。可以在 AST 上做些操作，这些操作能够集成到编译中，成为编译的一部分。插件是在运 行时由编译器加载的动态库，方便集成到构建系统中。
使用 Clang Plugins 一般都是希望能够完全控制 Clang AST，同时能够集成在编译流程中，可以影响编译的过程，进行中断或者提示。
应用：实现命名规范、代码规范等一些扩展功能

- **LibTooling**。是一个 C++ 接口，所写的工具不依赖于构建系统，可以作为一个命令单独使用。与 Clang Plugins 相比，LibTooling 无法影响编译过程；与 LibClang 相比，LibTooling 的接口没有那么稳定。
应用：做代码转换，比如把 OC 转 JavaScript 或 Swift；代码检查。

##### 2. Clang的优点
Clang 是 C、C++、Objective-C 的编译前端，而 Swift 有自己的编译前端 （也就是 Swift 前端多出的 SIL optimizer）。Clang 有哪些优势？
- 对于使用者来说，Clang 编译的速度非常快，对内存的使用率非常低，并且兼容 GCC。
- 对于代码诊断来说， Clang 也非常强大，Xcode 也是用的 Clang。使用 Clang 编译前端，可以精确地显示出问题所在的行和具体位置，并且可以确切地说明出现这个问题的原因，并指出错误的类型是什么，使得我们可以快速掌握问题的细节。这样的话，我们不用看源码，仅通过 Clang 突出标注的问题范围也能够了解到问题的情况。
- Clang 对 typedef 的保留和展开也处理得非常好。typedef 可以缩写很长的类型，保留 typedef 对于粗粒度诊断分析很有帮助。但有时候，我们还需要了解细节，对 typedef 进行展开即可。
- Fix-it 提示也是 Clang 提供的一种快捷修复源码问题的方式。在宏的处理上，很多宏都是深度嵌套的， Clang 会自动打印实例化信息和嵌套范围信息来帮助你进行宏的诊断和分析。
- Clang 的架构是模块化的。除了代码静态分析外，利用其输出的接口还可以开发用于代码转义、代码生成、代码重构的工具，方便与 IDE 进行集成。

Clang 是基于 C++ 开发的，如果你想要了解 Clang 的话，需要有一定的 C++ 基础。但是，Clang 源码本身质量非常高，有很多值得学习的地方，比如说目录清晰、功能解耦做得很好、分类清晰方便组合和复用、代码风格统一而且规范、注释量大便于阅读等。

### 1.3 Clang-LLVM架构

Clang-LLVM架构，即用Clang作为前端的LLVM(编译工具集)。

Clang-LLVM下，一个源文件的编译过程：

<img src="/images/compilelink/02.png" alt="01" style="zoom:65%;" />

iOS 开发完整的编译流程图：

<img src="/images/compilelink/03.png" alt="01" style="zoom:80%;" />

LLVM架构的主要组成部分：
- **前端**：前端用来获取源代码然后将它转变为某种中间表示，我们可以选择不同的编译器来作为LLVM的前端，如gcc，clang(Clang-LLVM)。
LLVM支持三种表达形式：人类可读的汇编(`.ll`后缀，是LLVM IR文件，其有自己的语法)、在C++中对象形式、序列化后的bitcode形式(`.bc`后缀)。

- **Pass**(v.通过/传递/变化 n.经过/通行证/**通道**/**流程**/**阶段**) ：是 LLVM 优化(optimize)工作的一个节点，一个节点做些事，一起加起来就构成了 LLVM 完整的优化和转化。
Pass用来将程序的中间表示之间相互变换。一般情况下，Pass可以用来优化代码，这部分通常是我们关注的部分。我们可以自己编写Pass，做一些代码混淆优化等操作。

- **后端**：后端用来生成实际的机器码。至3.4版本的LLVM已经支持多种后端指令集，比如主流的x86、x86-64、z/Architecture、ARM和PowerPC等

虽然如今大多数编译器都采用的是这种架构，但是LLVM不同的就是对于不同的语言它都提供了同一种中间表示。传统的编译器的架构如下:

<img src="/images/compilelink/04.png" alt="01" style="zoom:100%;" />

LLVM的架构如下：

<img src="/images/compilelink/05.png" alt="01" style="zoom:75%;" />

当编译器需要支持多种源代码和目标架构时，基于LLVM的架构，设计一门新的语言只需要去实现一个新的前端就行了，支持新的后端架构也只需要实现一个新的后端，其它部分完成可以复用，不用重新设计。在基于LLVM进行代码混淆时，只需要关注中间层代码(IR)表示。

### 1.4 应用

- iOS 开发中 Objective-C 是 Clang / LLVM 来编译的。
- swift 是 Swift / LLVM，其中 Swift 前端会多出 SIL optimizer，它会把 .swift 生成的中间代码 .sil 属于 High-Level IR， 因为 swift 在编译时就完成了方法绑定直接通过地址调用属于强类型语言，方法调用不再是像OC那样的消息发送，这样编译就可以获得更多的信息用在后面的后端优化上。
- Gallium3D 中使用 LLVM 进行 JIT 优化
- Xorg 中的 pixman 也有考虑使用 LLVM 优化执行速度
- LLVM-Lua 用LLVM 来编译 lua 代码
- gpuocelot 使用 LLVM 可以让 CUDA 程序无需重新编译就能够在多种 CPU 机器上跑。

下面，通过具体的代码、命令，来看一下iOS中源代码详细的编译、链接过程

## 二、编译、静态链接过程

> 从源码到可执行文件 — iOS应用编译、静态链接过程

我们在开发的时候的时候，如果想要生成一个可执行文件或应用，我们点击run就完事了，那么在点击run之后编译器背后又做了哪些事情呢？

我们先来一个例子：
```C
#include <stdio.h>
#define DEFINEEight 8

int main(){
    int eight = DEFINEEight;
    int six = 6;
    int rank = eight + six;
    printf("%d\n",rank);
    return 0;
}
```

上面这个文件，我们可以通过命令行直接编译，然后链接：
```bash
xcrun -sdk iphoneos clang -arch armv7 -F Foundation -fobjc-arc -c main.m -o main.o
xcrun -sdk iphoneos clang main.o -arch armv7 -fobjc-arc -framework Foundation -o main
```

然后将该可执行文件copy到手机目录 /usr/bin 下面：
```bash
xx-iPhone:/usr/bin root# ./main
14
```

下面深入剖析其中的过程。

### Clang常用命令与参数  

[参考链接](https://clang.llvm.org/docs/ClangCommandLineReference.html)

```c
// 查看编译的步骤
clang -ccc-print-phases main.m

// Rewrite Objective-C source to C++，将OC源代码重写为C++(仅供参考，与真正的运行时代码还是有细微差别的)
// 如果想了解真正的代码，可以使用-emit-llvm参数查看.ll中间代码
clang -rewrite-objc main.m

// 查看操作内部命令
clang -### main.m -o main

// 直接生成可执行文件
clang main.m // 默认生成的文件名为a.out
  /*
    参数：
    -cc1：Clang编译器前端具有几个额外的Clang特定功能，这些功能不通过GCC兼容性驱动程序接口公开。 -cc1参数表示将使用编译器前端，而不是驱动程序。 clang -cc1功能实现了核心编译器功能。
	-E：只进行预编译处理(preprocessor)
	-S：只进行预编译、编译工作
	-c：只进行预处理、编译、汇编工作
	-fmodules：允许modules的语言特性。
		在使用#include、#import时，会看到预处理时已经把宏替换了，并且导入了头文件。但是这样的话会引入很多不会去改变的系统库比如Foundation。
		所以有了pch预处理文件，可以在这里去引入一些通用的头文件。
		后来Xcode新建的项目里面去掉了pch文件，引入了moduels的概念，把一些通用的库打成modules的形式，然后导入。现在Xcode中默认是打开的，即编译源码时会加上-fmodules参数。也是因为modules机制的出现，pch不再默认自动创建。
		使用了该参数，在导入库的地方，只需要 @import Foundation; 就行
		可以看到使用了@import之后，clang -fmodules xx 生成的文件中，不再有上万行的系统库的代码引入，精简了很多。
	-fsyntax-only：防止编译器生成代码,只是语法级别的说明和修改
	-Xclang <arg>：向clang编译器传递参数
	-dump-tokens：运行预处理器,拆分内部代码段为各种token
	-ast-dump：构建抽象语法树AST,然后对其进行拆解和调试
	-fobjc-arc：为OC对象生成retain和release的调用
	-emit-llvm：使用LLVM描述汇编和对象文件
	-o <file>：输出到目标文件
   */
```

查看更多的`clang`使用方法可以在终端输入`clang --hep`查看,也可以点击下面的链接:https://link.jianshu.com/?t=https://gist.github.com/masuidrive/5231110

### 2.1 预处理（Preprocess）

预编译过程主要处理源代码文件中的以"#"开头的预编译指令，**不检查语法错误**。规则如下：

- 将所有的 “#define” 删除，并且展开所有的宏定义。 
- 处理所有条件预编译指令，比如 “#if”、“#ifdef”、“#elif”、“#else”、“#endif”。
- 处理 “#include” 预编译指令，将被包含的文件内容插入到(全部复制到)该预编译指令的位置。注意，这个过程是递归进行的，也就是说被包含的文件可能还包含其他文件。#include 可以导入任何(合法/不合法)文件，都能展开。
- 删除所有的注释“//”和“/* */”，会变成空行。 
- 保留所有的 #pragma 编译器指令，因为编译器须要使用它们。
- 添加行号和文件名标识，比如# 2 "main.m" 2，以便于编译时编译器产生调试用的行号信息及用于编译时产生编译错误或警告时能够显示行号。
	格式是“`# 行号 文件名 标志`”，参数解释如下：
  + 行号与文件名：表示从它后一行开始的内容来源于哪一个文件的哪一行
  + 标志：可以是1,2,3,4四个数字，每个数字的含义如下：
	1：表示新文件的开始
	2：表示从一个被包含的文件中返回
	3：表示后面的内容来自系统头文件
	4：表示后面的内容应当被当做一个隐式的extern 'C'块

经过预编译后的` .i 文件`不包含任何宏定义，因为所有的宏已经被展开，并且包含的文件也已经被插入到 .i 文件中。所以当我们无法判断宏定义是否正确或头文件包含是否正确时，可以查看预编译后的文件来确定问题。

可以通过执行以下命令，`-E`表示只进行预编译：
```bash
clang -E main.m 
# 或者 
clang -E -fmodules main.m # 此时需要源码中改为@import
```

执行完这个命令之后，我们会发现导入了很多的头文件内容。
```
......
# 408 "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/stdio.h" 2 3 4
# 2 "main.m" 2


int main(){
    int eight = 8;
    int six = 6;
    int rank = eight + six;
    printf("%d\n",rank);
    return 0;
}
```

可以看到上面的预处理已经把宏替换了，并且导入了头文件。

### 2.2 词法分析 (Lexical Analysis)

预处理之后，就是编译。编译过程就是把预处理完的文件进行一系列词法分析、语法分析、语义分析及优化后生产相应的汇编代码文件，这个过程往往是我们所说的整个程序构建的核心部分，也是最复杂的部分之一。

首先，Clang 会对代码进行词法分析，将代码切分成 Token。你可以在[这个链接](https://opensource.apple.com/source/lldb/lldb-69/llvm/tools/clang/include/clang/Basic/TokenKinds.def)
中，看到 Clang 定义的所有 Token 类型。我们可以把这些 Token 类型，分为下面这 4 类。 
  + 关键字：语法中的关键字，比如 if、else、while、for 等;
  + 标识符：变量名;
  + 字面量：值、数字、字符串; 
  + 特殊符号：加减乘除、左右括号等符号。

```
clang -fsyntax-only -Xclang -dump-tokens main.m
```
每一个标记都包含了对应的源码内容和其在源码中的位置。注意这里的位置是宏展开之前的位置，这样一来，如果编译过程中遇到什么问题，clang 能够在源码中指出出错的具体位置。
```
int 'int'	 [StartOfLine]	Loc=<main.m:4:1>
identifier 'main'	 [LeadingSpace]	Loc=<main.m:4:5>
l_paren '('		Loc=<main.m:4:9>
r_paren ')'		Loc=<main.m:4:10>
l_brace '{'		Loc=<main.m:4:11>
int 'int'	 [StartOfLine] [LeadingSpace]	Loc=<main.m:5:5>
identifier 'eight'	 [LeadingSpace]	Loc=<main.m:5:9>
equal '='	 [LeadingSpace]	Loc=<main.m:5:15>
numeric_constant '8'	 [LeadingSpace]	Loc=<main.m:5:17 <Spelling=main.m:2:21>>
semi ';'		Loc=<main.m:5:28>
int 'int'	 [StartOfLine] [LeadingSpace]	Loc=<main.m:6:5>
identifier 'six'	 [LeadingSpace]	Loc=<main.m:6:9>
equal '='	 [LeadingSpace]	Loc=<main.m:6:13>
numeric_constant '6'	 [LeadingSpace]	Loc=<main.m:6:15>
semi ';'		Loc=<main.m:6:16>
int 'int'	 [StartOfLine] [LeadingSpace]	Loc=<main.m:7:5>
identifier 'rank'	 [LeadingSpace]	Loc=<main.m:7:9>
equal '='	 [LeadingSpace]	Loc=<main.m:7:14>
identifier 'eight'	 [LeadingSpace]	Loc=<main.m:7:16>
plus '+'	 [LeadingSpace]	Loc=<main.m:7:22>
identifier 'six'	 [LeadingSpace]	Loc=<main.m:7:24>
semi ';'		Loc=<main.m:7:27>
identifier 'printf'	 [StartOfLine] [LeadingSpace]	Loc=<main.m:8:5>
l_paren '('		Loc=<main.m:8:11>
string_literal '"%d\n"'		Loc=<main.m:8:12>
comma ','		Loc=<main.m:8:18>
identifier 'rank'		Loc=<main.m:8:19>
r_paren ')'		Loc=<main.m:8:23>
semi ';'		Loc=<main.m:8:24>
return 'return'	 [StartOfLine] [LeadingSpace]	Loc=<main.m:9:5>
numeric_constant '0'	 [LeadingSpace]	Loc=<main.m:9:12>
semi ';'		Loc=<main.m:9:13>
r_brace '}'	 [StartOfLine]	Loc=<main.m:10:1>
eof ''		Loc=<main.m:10:2>
```

### 2.3 语法、语义分析
这个阶段有两个模块Parser(语法syntax分析器)、Sema(语义分析Semantic)配合完成：
- Parser：遍历每个Token做词句分析，根据当前语言的语法，验证语法是否正确，最后生成一个 节点（Nodes）并记录相关的信息。
- Semantic：在Lex 跟 syntax Analysis之后, 已经确保 词 句已经是正确的形式，semantic 接着做return values, size boundaries, uninitialized variables 等检查，如果发现语义上有错误给出提示；如果没有错误就会将 Token 按照语法组合成语义，生成 Clang 语义节点(Nodes)，然后将这些节点按照层级关系构成抽象语法树(AST)。

AST可以说是Clang的核心，大部分的优化, 判断都在AST处理（例如寻找Class, 替换代码...等)。此步骤会将 Clang Attr  转换成 AST 上的 AttributeList，能在clang插件上透过 `Decl::getAttr<T>` 获取

> Clang Attributes：是 Clang 提供的一种源码注解，方便开发者向编译器表达某种要求，参与控制如 Static Analyzer、Name Mangling、Code Generation 等过程, 一般以 `__attribute__(xxx)` 的形式出现在代码中, Ex: `NS_CLASS_AVAILABLE_IOS(9_0)`

结构跟其他Compiler的AST相同。与其他编译器不同的是 Clang的AST是由C++构成类似Class、Variable的层级表示，其他的则是以汇编语言编写。这代表着AST也能有对应的api，这让AST操作, 获取信息都比较容易，甚至还夹带着地址跟代码位置。

> AST Context: 存储所有AST相关资讯, 且提供ASTMatcher等遍历方法

在 Clang的定义中，节点主要分成：Type(类型)，Decl(声明)，Stmt(陈述)，其他的都是这三种的派生。Type具体到某个语言的类型时便可以派生出 PointerType(指针类型)、ObjCObjectType(objc对象类型)、BuiltinType(内置基础数据类型)这些表示。通过这三者的联结、重复或选择（alternative)就能构成一门编程语言。举个例子，下图的一段代码：详细可以看[了解 Clang AST](https://www.stephenw.cc/2018/01/08/clang-ast/)

<img src="/images/compilelink/06.png" alt="01" style="zoom:70%;" />

FunctionDecl、ParmVarDecl 都是基于 Decl派生的类，CompoundStmt、ReturnStmt、DeclStmt都是基于 Stmt派生的类。）

从上图中可以看到：
- 一个FunctionDecl（函数的实现）由一个 ParmVarDecl联结 CompoundStmt组成。
- 函数的 CompoundStmt 由 DeclStmt和 ReturnStmt联结组成。
- 还可以发现这段代码的ParmVarDecl由 BuiltinType 和一个标识符字面量联结组成。

很明显一门编程语言中还有很多其他形态，我们都可以用这种方式描述出来。所以说从抽象的角度看，拥有无限种形态的编程语言便可以用有限的形式来表示。

```bash
clang -fsyntax-only -Xclang -ast-dump main.m
```
```
......
`-FunctionDecl 0x7fcbb9947b20 <main.m:4:1, line:10:1> line:4:5 main 'int ()'
  `-CompoundStmt 0x7fcbb9947fc8 <col:11, line:10:1>
    |-DeclStmt 0x7fcbb9947c50 <line:5:5, col:28>
    | `-VarDecl 0x7fcbb9947bd0 <col:5, line:2:21> line:5:9 used eight 'int' cinit
    |   `-IntegerLiteral 0x7fcbb9947c30 <line:2:21> 'int' 8
    |-DeclStmt 0x7fcbb9947d00 <line:6:5, col:16>
    | `-VarDecl 0x7fcbb9947c80 <col:5, col:15> col:9 used six 'int' cinit
    |   `-IntegerLiteral 0x7fcbb9947ce0 <col:15> 'int' 6
    |-DeclStmt 0x7fcbb9947e20 <line:7:5, col:27>
    | `-VarDecl 0x7fcbb9947d30 <col:5, col:24> col:9 used rank 'int' cinit
    |   `-BinaryOperator 0x7fcbb9947e00 <col:16, col:24> 'int' '+'
    |     |-ImplicitCastExpr 0x7fcbb9947dd0 <col:16> 'int' <LValueToRValue>
    |     | `-DeclRefExpr 0x7fcbb9947d90 <col:16> 'int' lvalue Var 0x7fcbb9947bd0 'eight' 'int'
    |     `-ImplicitCastExpr 0x7fcbb9947de8 <col:24> 'int' <LValueToRValue>
    |       `-DeclRefExpr 0x7fcbb9947db0 <col:24> 'int' lvalue Var 0x7fcbb9947c80 'six' 'int'
    |-CallExpr 0x7fcbb9947f20 <line:8:5, col:23> 'int'
    | |-ImplicitCastExpr 0x7fcbb9947f08 <col:5> 'int (*)(const char *, ...)' <FunctionToPointerDecay>
    | | `-DeclRefExpr 0x7fcbb9947e38 <col:5> 'int (const char *, ...)' Function 0x7fcbb9932e70 'printf' 'int (const char *, ...)'
    | |-ImplicitCastExpr 0x7fcbb9947f68 <col:12> 'const char *' <NoOp>
    | | `-ImplicitCastExpr 0x7fcbb9947f50 <col:12> 'char *' <ArrayToPointerDecay>
    | |   `-StringLiteral 0x7fcbb9947e98 <col:12> 'char [4]' lvalue "%d\n"
    | `-ImplicitCastExpr 0x7fcbb9947f80 <col:19> 'int' <LValueToRValue>
    |   `-DeclRefExpr 0x7fcbb9947eb8 <col:19> 'int' lvalue Var 0x7fcbb9947d30 'rank' 'int'
    `-ReturnStmt 0x7fcbb9947fb8 <line:9:5, col:12>
      `-IntegerLiteral 0x7fcbb9947f98 <col:12> 'int' 0
```
在抽象语法树中的每个节点都标注了其对应源码中的位置，如果产生了什么问题，clang 可以定位到问题所在处的源码位置。

语法树直观图:

<img src="/images/compilelink/07.png" alt="01" style="zoom:90%;" />

#### 2.3.1 静态分析 (Static Analyzer)

一旦编译器把源码生成了抽象语法树，编译器可以对这棵树做分析处理，以找出代码中的错误，比如类型检查：即检查程序中是否有类型错误。例如：如果代码中给某个对象发送了一个消息，编译器会检查这个对象是否实现了这个消息（函数、方法）。此外，clang 对整个程序还做了其它更高级的一些分析，以确保程序没有错误。
```
OVERVIEW: Clang Static Analyzer Checkers List

USAGE: -analyzer-checker <CHECKER or PACKAGE,...>

CHECKERS:
  alpha.clone.CloneChecker        Reports similar pieces of code.
  alpha.core.BoolAssignment       Warn about assigning non-{0,1} values to Boolean variables
  alpha.core.CallAndMessageUnInitRefArg      Check for logical errors for function calls and Objective-C message expressions (e.g., uninitialized arguments, null function pointers, and pointer to undefined variables)
  alpha.core.CastSize             Check when casting a malloc'ed type T, whether the size is a multiple of the size of T
  ...
```
[scan-build](http://clang-analyzer.llvm.org/scan-build.html) 是用于静态分析代码的工具，它包含在 clang 的源码包中。使用scan-build可以从命令行运行分析器，比如：
```
roten@localhost scan-build % ./scan-build --use-analyzer=xcode xcodebuild -project Demo123.xcodeproj    // 需要设置 --use-analyzer指定 clang 的路径

scan-build: Using '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang' for static analysis
Build settings from command line:
    CLANG_ANALYZER_EXEC = /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang
    CLANG_ANALYZER_OTHER_FLAGS = 
    CLANG_ANALYZER_OUTPUT = plist-html
    CLANG_ANALYZER_OUTPUT_DIR = /var/folders/1r/n7kwlmgn74l3pvvht646f6fm0000gp/T/scan-build-2020-09-01-140523-22105-1
    RUN_CLANG_STATIC_ANALYZER = YES

note: Using new build system
note: Planning build
note: Constructing build description
Build system information
....

** BUILD SUCCEEDED **

scan-build: Removing directory '/var/folders/1r/n7kwlmgn74l3pvvht646f6fm0000gp/T/scan-build-2020-09-01-140523-22105-1' because it contains no reports.
scan-build: No bugs found.
```
关于静态分析更多可以查看 ：[Clang 静态分析器](http://clang-analyzer.llvm.org/)

clang 完成代码的标记，解析和分析后，接着就会生成 LLVM 代码。

### 2.4 IR代码生成 (CodeGen)

CodeGen负责将语法树从顶至下遍历，翻译成LLVM IR，LLVM IR是Frontend的输出，也是LLVM Backerend的输入，桥接前后端。

```bash
clang -S -fobjc-arc -emit-llvm main.m -o main.ll
```
```assembly
; ModuleID = 'main.m'
source_filename = "main.m"
target datalayout = "e-m:o-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-apple-macosx10.15.0"

@.str = private unnamed_addr constant [4 x i8] c"%d\0A\00", align 1

; Function Attrs: noinline optnone ssp uwtable
define i32 @main() #0 {
  %1 = alloca i32, align 4
  %2 = alloca i32, align 4
  %3 = alloca i32, align 4
  %4 = alloca i32, align 4
  store i32 0, i32* %1, align 4
  store i32 8, i32* %2, align 4
  store i32 6, i32* %3, align 4
  %5 = load i32, i32* %2, align 4
  %6 = load i32, i32* %3, align 4
  %7 = add nsw i32 %5, %6
  store i32 %7, i32* %4, align 4
  %8 = load i32, i32* %4, align 4
  %9 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([4 x i8], [4 x i8]* @.str, i32 0, i32 0), i32 %8)
  ret i32 0
}

declare i32 @printf(i8*, ...) #1

attributes #0 = { noinline optnone ssp uwtable "correctly-rounded-divide-sqrt-fp-math"="false" "darwin-stkchk-strong-link" "disable-tail-calls"="false" "less-precise-fpmad"="false" "min-legal-vector-width"="0" "no-frame-pointer-elim"="true" "no-frame-pointer-elim-non-leaf" "no-infs-fp-math"="false" "no-jump-tables"="false" "no-nans-fp-math"="false" "no-signed-zeros-fp-math"="false" "no-trapping-math"="false" "probe-stack"="___chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="penryn" "target-features"="+cx16,+fxsr,+mmx,+sahf,+sse,+sse2,+sse3,+sse4.1,+ssse3,+x87" "unsafe-fp-math"="false" "use-soft-float"="false" }
attributes #1 = { "correctly-rounded-divide-sqrt-fp-math"="false" "darwin-stkchk-strong-link" "disable-tail-calls"="false" "less-precise-fpmad"="false" "no-frame-pointer-elim"="true" "no-frame-pointer-elim-non-leaf" "no-infs-fp-math"="false" "no-nans-fp-math"="false" "no-signed-zeros-fp-math"="false" "no-trapping-math"="false" "probe-stack"="___chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="penryn" "target-features"="+cx16,+fxsr,+mmx,+sahf,+sse,+sse2,+sse3,+sse4.1,+ssse3,+x87" "unsafe-fp-math"="false" "use-soft-float"="false" }

!llvm.module.flags = !{!0, !1, !2, !3, !4, !5, !6, !7}
!llvm.ident = !{!8}

!0 = !{i32 2, !"SDK Version", [2 x i32] [i32 10, i32 15]}
!1 = !{i32 1, !"Objective-C Version", i32 2}
!2 = !{i32 1, !"Objective-C Image Info Version", i32 0}
!3 = !{i32 1, !"Objective-C Image Info Section", !"__DATA,__objc_imageinfo,regular,no_dead_strip"}
!4 = !{i32 4, !"Objective-C Garbage Collection", i32 0}
!5 = !{i32 1, !"Objective-C Class Properties", i32 64}
!6 = !{i32 1, !"wchar_size", i32 4}
!7 = !{i32 7, !"PIC Level", i32 2}
!8 = !{!"Apple clang version 11.0.0 (clang-1100.0.33.12)"}
```

#### 2.4.1 中间代码优化 (Optimize)

可以在中间代码层次去做一些优化工作，我们在Xcode的编译设置里面也可以设置优化级别`-O1`,`-O3`,`-Os`对应着不同的入参，有比如类似死代码清理，内联化，表达式重组，循环变量移动这样的 Pass。Pass就是LLVM系统转化和优化的工作的一个节点，每个节点做一些工作，这些工作加起来就构成了LLVM整个系统的优化和转化。

<img src="/images/compilelink/08.png" alt="01" style="zoom:95%;" />

<img src="/images/compilelink/09.png" alt="01" style="zoom:85%;" />

我们还可以去写一些自己的Pass，官方有比较完整的 Pass 教程： [Writing an LLVM Pass — LLVM 5 documentation](https://releases.llvm.org/5.0.2/docs/WritingAnLLVMPass.html)。

### 2.5 生成字节码 (LLVM Bitcode)

我们在Xcode7中默认生成bitcode就是这种的中间形式存在，开启了bitcode，那么苹果后台拿到的就是这种中间代码，苹果可以对bitcode做一个进一步的优化，如果有新的后端架构，仍然可以用这份bitcode去生成。

> Bitcode是编译后的程序的中间表现，包含Bitcode并上传到App Store Connect的Apps会在App Store上编译和链接。包含Bitcode可以在不提交新版本App的情况下，允许Apple在将来的时候再次优化你的App 二进制文件。
> 对于iOS Apps，Enable bitcode 默认为YES，是可选的（可以改为NO）。对于WatchOS和tvOS，bitcode是强制的。如果你的App支持bitcode，App Bundle（项目中所有的target）中的所有的Apps和frameworks都需要包含Bitcode。

```bash
clang -emit-llvm -c main.m -o main.bc
```

<img src="/images/compilelink/10.png" alt="01" style="zoom:90%;" />

### 2.6 生成相关汇编

```bash
clang -S -fobjc-arc main.m -o main.s
```
```arm
	.section	__TEXT,__text,regular,pure_instructions
	.build_version macos, 10, 15	sdk_version 10, 15
	.globl	_main                   ## -- Begin function main
	.p2align	4, 0x90
_main:                                  ## @main
	.cfi_startproc
## %bb.0:
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$32, %rsp
	movl	$0, -4(%rbp)
	movl	$8, -8(%rbp)
	movl	$6, -12(%rbp)
	movl	-8(%rbp), %eax
	addl	-12(%rbp), %eax
	movl	%eax, -16(%rbp)
	movl	-16(%rbp), %esi
	leaq	L_.str(%rip), %rdi
	movb	$0, %al
	callq	_printf
	xorl	%esi, %esi
	movl	%eax, -20(%rbp)         ## 4-byte Spill
	movl	%esi, %eax
	addq	$32, %rsp
	popq	%rbp
	retq
	.cfi_endproc
                                        ## -- End function
	.section	__TEXT,__cstring,cstring_literals
L_.str:                                 ## @.str
	.asciz	"%d\n"

	.section	__DATA,__objc_imageinfo,regular,no_dead_strip
L_OBJC_IMAGE_INFO:
	.long	0
	.long	64


.subsections_via_symbols
```

### 2.7 生成目标文件
编译阶段完成，接下来就是汇编阶段。汇编器是将汇编代码转变成机器可以执行的指令，每一个汇编语句几乎都对应一条机器指令。所以汇编器的汇编过程相对于编译器来讲比较简单，它没有复杂的语法，也没有语义，也不需要做指令优化，只是根据汇编指令和机器指令的对照表一一翻译就可以了。

这些文件以 .o 结尾。如果用 Xcode 构建应用程序，可以在工程的 derived data 目录中，Objects-normal 文件夹下找到这些文件。

```bash
clang -fmodules -c main.m -o main.o
```
<img src="/images/compilelink/11.png" alt="01" style="zoom:90%;" />

### 2.8 生成可执行文件
```bash
clang main.o -o main  # 生成可执行文件
./main  # 执行 可执行文件 代码
```
```bash
打印结果：14
```

### 2.9 记录一个Clang命令报错
```
/usr/local/include/stdint.h:59:11: error: #include nested too deeply  
# include <stdint.h>  
          ^  
/usr/local/include/stdint.h:82:11: error: #include nested too deeply
# include <inttypes.h>
          ^
...
```

解决方案：

1. 可能是xcode-select 没装，于是执行xcode-select --install 进行工具安装。

2. 如果问题还在。brew doctor一下就行了

   ```bash
   mkdir /tmp/includes
   brew doctor 2>&1 | grep "/usr/local/include" | awk '{$1=$1;print}' | xargs -I _ mv _ /tmp/includes 
   ```

   参考链接：https://github.com/SOHU-Co/kafka-node/issues/881

## 三、小结：iOS从编码到打包

- 首先我们编写完成代码之后，会通过LLVM编译器预处理我们的代码，比如将宏放在指定的位置
- 预处理结束之后，LLVM会对代码进行词法分析和语法分析，生成AST。AST是抽象语法树，主要用来进行快速遍历，实现静态代码检查的功能。
- AST会生成IR，IR是一种更加接近机器码的语言，通过IR可以生成不同平台的机器码。对于iOS平台，IR生成的可执行文件就是Mach-O.
- 然后通过链接器将符号和地址绑定在一起，并且将项目中的多个Mach-O文件(目标文件)合并成一个Mach-O文件(可执行文件)。(**关于Mach-O、链接下一节讲**)
- 将可执行文件与资源文件、storyboard、xib等打包，最后通过签名等操作生成.app文件，然后对.app文件进行压缩就生成了我们可以安装的ipa包。
- 当然，ipa包的安装途径有两种：
  + 通过开发者账号上传到App Store，然后在App Store上下载安装。
  + 通过PP助手、iFunBox、Xcode等工具来安装


## 四、参考链接
- [关于LLVM，这些东西你必须知道!](http://blog.alonemonkey.com/2016/12/21/learning-llvm/) 本篇文章大部分来自此文章。按照自己的理解记忆方式删减、添加了一些知识。原文中还补充有：
  + Clang的三大基础设施(libclang、LibTooling、ClangPlugin)的应用、代码示例
  + 动手写Pass的代码示例
- [深入剖析 iOS 编译 Clang / LLVM — 戴铭](https://xiaozhuanlan.com/topic/4916328705)
- [《程序员的自我修养》]()
- [(Xcode) 編譯器小白筆記 - LLVM前端Clang](https://juejin.im/post/6844903716709990414#heading-6)