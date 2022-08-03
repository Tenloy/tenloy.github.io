---
title: '[转] Make 命令的使用与NodeJS案例'
date: 2021-10-02 04:25:45
urlname: makefile.html
tags:
categories:
  - 编译链接与装载
---

> 原文链接：[Make 命令教程 — 阮一峰](https://www.ruanyifeng.com/blog/2015/02/make.html)

代码变成可执行文件，叫做编译（compile）；先编译这个，还是先编译那个（即编译的安排），叫做构建（build）。

[Make](https://en.wikipedia.org/wiki/Make_(software))是最常用的构建工具，诞生于1977年，主要用于C语言的项目。但是实际上 ，任何只要某个文件有变化，就要重新构建的项目，都可以用Make构建。

本文介绍Make命令的用法，从简单的讲起，不需要任何基础，只要会使用命令行，就能看懂。我的参考资料主要是Isaac Schlueter的[《Makefile文件教程》](https://gist.github.com/isaacs/62a2d1825d04437c6f08)和[《GNU Make手册》](https://www.gnu.org/software/make/manual/make.html)。

# 一、Make的概念

Make这个词，英语的意思是"制作"。Make命令直接用了这个意思，就是要做出某个文件。比如，要做出文件a.txt，就可以执行下面的命令。

```bash
$ make a.txt
```

但是，如果你真的输入这条命令，它并不会起作用。因为Make命令本身并不知道，如何做出a.txt，需要有人告诉它，如何调用其他命令完成这个目标。

比如，假设文件 a.txt 依赖于 b.txt 和 c.txt ，是后面两个文件连接（cat命令）的产物。那么，make 需要知道下面的规则。

```bash
a.txt: b.txt c.txt
    cat b.txt c.txt > a.txt
```

也就是说，make a.txt 这条命令的背后，实际上分成两步：第一步，确认 b.txt 和 c.txt 必须已经存在，第二步使用 cat 命令 将这个两个文件合并，输出为新文件。

**像这样的规则，都写在一个叫做Makefile的文件中，Make命令依赖这个文件进行构建。Makefile文件也可以写为makefile， 或者用命令行参数指定为其他文件名。**

```bash
$ make -f rules.txt
# 或者
$ make --file=rules.txt
```

上面代码指定make命令依据rules.txt文件中的规则，进行构建。

总之，make只是一个根据指定的Shell命令进行构建的工具。它的规则很简单，你规定要构建哪个文件、它依赖哪些源文件，当那些文件有变动时，如何重新构建它。

# 二、Makefile文件的格式

很多开发者不了解 Makefile 是什么，这个其实很正常，因为很多集成开发环境（IDE）已经内置了 Makefile，或者说会自动生成 Makefile，我们不用去手动编写。

那么，究竟什么是 Makefile 呢？**Makefile 可以简单的认为是一个工程文件的编译规则，描述了整个工程的编译和链接等规则。**其中包含了那些文件需要编译，那些文件不需要编译，那些文件需要先编译，那些文件需要后编译，那些文件需要重建等等。编译整个工程需要涉及到的，在 Makefile 中都可以进行描述。换句话说，Makefile 可以使得我们的项目工程的编译变得自动化，不需要每次都手动输入一堆源文件和参数。

构建规则都写在Makefile文件里面，要学会如何Make命令，就必须学会如何编写Makefile文件。

## 2.1 概述

Makefile文件由一系列规则（rules）构成。每条规则的形式如下。

```bash
<target> : <prerequisites> 
[tab]  <commands>
```

上面第一行冒号前面的部分，叫做"目标"（target），冒号后面的部分叫做"前置条件"（prerequisites）；第二行必须由一个tab键起首，后面跟着"命令"（commands）。

"目标"是必需的，不可省略；"前置条件"和"命令"都是可选的，但是两者之中必须至少存在一个。

每条规则就明确两件事：构建目标的前置条件是什么，以及如何构建。下面就详细讲解，每条规则的这三个组成部分。

## 2.2 目标（target）

一个目标（target）就构成一条规则。目标通常是文件名，指明Make命令所要构建的对象，比如上文的 a.txt 。目标可以是一个文件名，也可以是多个文件名，之间用空格分隔。

除了文件名，目标还可以是某个操作的名字，这称为"伪目标"（phony target）。

```bash
clean:
      rm *.o
```

上面代码的目标是clean，它不是文件名，而是一个操作的名字，属于"伪目标 "，作用是删除对象文件。

```bash
$ make  clean
```

但是，如果当前目录中，正好有一个文件叫做clean，那么这个命令不会执行。因为Make发现clean文件已经存在，就认为没有必要重新构建了，就不会执行指定的rm命令。

为了避免这种情况，可以明确声明clean是"伪目标"，写法如下。

```bash
.PHONY: clean
clean:
        rm *.o temp
```

声明clean是"伪目标"之后，make就不会去检查是否存在一个叫做clean的文件，而是每次运行都执行对应的命令。像.PHONY这样的内置目标名还有不少，可以查看[手册](https://www.gnu.org/software/make/manual/html_node/Special-Targets.html#Special-Targets)。

**如果Make命令运行时没有指定目标，默认会执行Makefile文件的第一个目标。**

```bash
$ make
```

上面代码执行Makefile文件的第一个目标。

## 2.3 前置条件（prerequisites）

前置条件通常是一组文件名，之间用空格分隔。它指定了"目标"是否重新构建的判断标准：只要有一个前置文件不存在，或者有过更新（前置文件的last-modification时间戳比目标的时间戳新），"目标"就需要重新构建。

```bash
result.txt: source.txt
    cp source.txt result.txt
```

上面代码中，构建 result.txt 的前置条件是 source.txt 。如果当前目录中，source.txt 已经存在，那么`make result.txt`可以正常运行，否则必须再写一条规则，来生成 source.txt 。

```bash
source.txt:
    echo "this is the source" > source.txt
```

上面代码中，source.txt后面没有前置条件，就意味着它跟其他文件都无关，只要这个文件还不存在，每次调用`make source.txt`，它都会生成。

```bash
$ make result.txt
$ make result.txt
```

上面命令连续执行两次`make result.txt`。第一次执行会先新建 source.txt，然后再新建 result.txt。第二次执行，Make发现 source.txt 没有变动（时间戳晚于 result.txt），就不会执行任何操作，result.txt 也不会重新生成。

如果需要生成多个文件，往往采用下面的写法。

```bash
source: file1 file2 file3
```

上面代码中，source 是一个伪目标，只有三个前置文件，没有任何对应的命令。

```bash
$ make source
```

执行`make source`命令后，就会一次性生成 file1，file2，file3 三个文件。这比下面的写法要方便很多。

```bash
$ make file1
$ make file2
$ make file3
```

## 2.4 命令（commands）

命令（commands）表示如何更新目标文件，由一行或多行的Shell命令组成。它是构建"目标"的具体指令，它的运行结果通常就是生成目标文件。

每行命令之前必须有一个tab键。如果想用其他键，可以用内置变量.RECIPEPREFIX声明。

```bash
.RECIPEPREFIX = >
all:
> echo Hello, world
```

上面代码用.RECIPEPREFIX指定，大于号（>）替代tab键。所以，每一行命令的起首变成了大于号，而不是tab键。

需要注意的是，每行命令在一个单独的shell中执行。这些Shell之间没有继承关系。

```bash
var-lost:
    export foo=bar
    echo "foo=[$$foo]"
```

上面代码执行后（`make var-lost`），取不到foo的值。因为两行命令在两个不同的进程执行。一个解决办法是将两行命令写在一行，中间用分号分隔。

```bash
var-kept:
    export foo=bar; echo "foo=[$$foo]"
```

另一个解决办法是在换行符前加反斜杠转义。

```bash
var-kept:
    export foo=bar; \
    echo "foo=[$$foo]"
```

最后一个方法是加上`.ONESHELL:`命令。

```bash
.ONESHELL:
var-kept:
    export foo=bar; 
    echo "foo=[$$foo]"
```

# 三、Makefile文件的语法

## 3.1 注释

井号（#）在Makefile中表示注释。

```bash
# 这是注释
result.txt: source.txt
    # 这是注释
    cp source.txt result.txt # 这也是注释
```

## 3.2 回声（echoing）

正常情况下，make会打印每条命令，然后再执行，这就叫做回声（echoing）。

```bash
test:
    # 这是测试
```

执行上面的规则，会得到下面的结果。

```bash
$ make test
# 这是测试
```

在命令的前面加上@，就可以关闭回声。

```bash
test:
    @# 这是测试
```

现在再执行`make test`，就不会有任何输出。

由于在构建过程中，需要了解当前在执行哪条命令，所以通常只在注释和纯显示的echo命令前面加上@。

```bash
test:
    @# 这是测试
    @echo TODO
```

## 3.3 通配符

通配符（wildcard）用来指定一组符合条件的文件名。Makefile 的通配符与 Bash 一致，主要有星号（*）、问号（？）和 [...] 。比如， *.o 表示所有后缀名为o的文件。

```bash
clean:
        rm -f *.o
```

## 3.4 模式匹配

Make命令允许对文件名，进行类似正则运算的匹配，主要用到的匹配符是%。比如，假定当前目录下有 f1.c 和 f2.c 两个源码文件，需要将它们编译为对应的对象文件。

```bash
%.o: %.c
```

等同于下面的写法。

```bash
f1.o: f1.c
f2.o: f2.c
```

使用匹配符%，可以将大量同类型的文件，只用一条规则就完成构建。

## 3.5 变量和赋值符

Makefile 允许使用等号自定义变量。

```bash
txt = Hello World
test:
    @echo $(txt)
```

上面代码中，变量 txt 等于 Hello World。调用时，变量需要放在 $( ) 之中。

调用Shell变量，需要在美元符号前，再加一个美元符号，这是因为Make命令会对美元符号转义。

```bash
test:
    @echo $$HOME
```

有时，变量的值可能指向另一个变量。

```bash
v1 = $(v2)
```

上面代码中，变量 v1 的值是另一个变量 v2。这时会产生一个问题，v1 的值到底在定义时扩展（静态扩展），还是在运行时扩展（动态扩展）？如果 v2 的值是动态的，这两种扩展方式的结果可能会差异很大。

为了解决类似问题，Makefile一共提供了四个赋值运算符 （=、:=、？=、+=），它们的区别请看[StackOverflow](https://stackoverflow.com/questions/448910/makefile-variable-assignment)。

```bash
VARIABLE = value
# 在执行时扩展，允许递归扩展。

VARIABLE := value
# 在定义时扩展。

VARIABLE ?= value
# 只有在该变量为空时才设置值。

VARIABLE += value
# 将值追加到变量的尾端。
```

## 3.6 内置变量（Implicit Variables）

Make命令提供一系列内置变量，比如，$(CC) 指向当前使用的编译器，$(MAKE) 指向当前使用的Make工具。这主要是为了跨平台的兼容性，详细的内置变量清单见[手册](https://www.gnu.org/software/make/manual/html_node/Implicit-Variables.html)。

```bash
output:
    $(CC) -o output input.c
```

## 3.7 自动变量（Automatic Variables）

Make命令还提供一些自动变量，它们的值与当前规则有关。主要有以下几个。

### 1. $@

$@指代当前目标，就是Make命令当前构建的那个目标。比如，`make foo`的 $@ 就指代foo。

```bash
a.txt b.txt: 
    touch $@
```

等同于下面的写法。

```bash
a.txt:
    touch a.txt
b.txt:
    touch b.txt
```

### 2. $<

$< 指代第一个前置条件。比如，规则为 t: p1 p2，那么$< 就指代p1。

```bash
a.txt: b.txt c.txt
    cp $< $@ 
```

等同于下面的写法。

```bash
a.txt: b.txt c.txt
    cp b.txt a.txt 
```

### 3. $?

$? 指代比目标更新的所有前置条件，之间以空格分隔。比如，规则为 t: p1 p2，其中 p2 的时间戳比 t 新，$?就指代p2。

### 4. $^

$^ 指代所有前置条件，之间以空格分隔。比如，规则为 t: p1 p2，那么 $^ 就指代 p1 p2 。

### 5. $*

$* 指代匹配符 % 匹配的部分， 比如% 匹配 f1.txt 中的f1 ，$* 就表示 f1。

### 6. $(@D) 和 $(@F)

$(@D) 和 $(@F) 分别指向 $@ 的目录名和文件名。比如，$@是 src/input.c，那么$(@D) 的值为 src ，$(@F) 的值为 input.c。

### 7. $(<D) 和 $(<F)

$(<D) 和 $(<F) 分别指向 $< 的目录名和文件名。

所有的自动变量清单，请看[手册](https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html)。下面是自动变量的一个例子。

```bash
dest/%.txt: src/%.txt
    @[ -d dest ] || mkdir dest
    cp $< $@
```

上面代码将 src 目录下的 txt 文件，拷贝到 dest 目录下。首先判断 dest 目录是否存在，如果不存在就新建，然后，$< 指代前置文件（src/%.txt）， $@ 指代目标文件（dest/%.txt）。

## 3.8 判断和循环

Makefile使用 Bash 语法，完成判断和循环。

```bash
ifeq ($(CC),gcc)
  libs=$(libs_for_gcc)
else
  libs=$(normal_libs)
endif
```

上面代码判断当前编译器是否 gcc ，然后指定不同的库文件。

```bash
LIST = one two three
all:
    for i in $(LIST); do \
        echo $$i; \
    done

# 等同于

all:
    for i in one two three; do \
        echo $i; \
    done
```

上面代码的运行结果。

```bash
one
two
three
```

## 3.9 函数

Makefile 还可以使用函数，格式如下。

```bash
$(function arguments)
# 或者
${function arguments}
```

Makefile提供了许多[内置函数](https://www.gnu.org/software/make/manual/html_node/Functions.html)，可供调用。下面是几个常用的内置函数。

### 1. shell 函数

shell 函数用来执行 shell 命令

```bash
srcfiles := $(shell echo src/{00..99}.txt)
```

### 2. wildcard 函数

wildcard 函数用来在 Makefile 中，替换 Bash 的通配符。

```bash
srcfiles := $(wildcard src/*.txt)
```

### 3. subst 函数

subst 函数用来文本替换，格式如下。

```bash
$(subst from,to,text)
```

下面的例子将字符串"feet on the street"替换成"fEEt on the strEEt"。

```bash
$(subst ee,EE,feet on the street)
```

下面是一个稍微复杂的例子。

```bash
comma:= ,
empty:=
# space变量用两个空变量作为标识符，当中是一个空格
space:= $(empty) $(empty)
foo:= a b c
bar:= $(subst $(space),$(comma),$(foo))
# bar is now `a,b,c'.
```

### 4. patsubst函数

patsubst 函数用于模式匹配的替换，格式如下。

```bash
$(patsubst pattern,replacement,text)
```

下面的例子将文件名"x.c.c bar.c"，替换成"x.c.o bar.o"。

```bash
$(patsubst %.c,%.o,x.c.c bar.c)
```

### 5 替换后缀名

替换后缀名函数的写法是：变量名 + 冒号 + 后缀名替换规则。它实际上patsubst函数的一种简写形式。

```bash
min: $(OUTPUT:.js=.min.js)
```

上面代码的意思是，将变量OUTPUT中的后缀名 .js 全部替换成 .min.js 。

# 四、Makefile 的实例

## 4.1 执行多个目标

```bash
.PHONY: cleanall cleanobj cleandiff

cleanall : cleanobj cleandiff
        rm program

cleanobj :
        rm *.o

cleandiff :
        rm *.diff
```

上面代码可以调用不同目标，删除不同后缀名的文件，也可以调用一个目标（cleanall），删除所有指定类型的文件。

## 4.2 编译C语言项目

```bash
edit : main.o kbd.o command.o display.o 
    cc -o edit main.o kbd.o command.o display.o

main.o : main.c defs.h
    cc -c main.c
kbd.o : kbd.c defs.h command.h
    cc -c kbd.c
command.o : command.c defs.h command.h
    cc -c command.c
display.o : display.c defs.h
    cc -c display.c

clean :
     rm edit main.o kbd.o command.o display.o

.PHONY: edit clean
```

# 五、CMake、NMake介绍

make工具就根据makefile文件中的命令进行编译和链接的。

makefile在一些简单的工程完全可以人工拿下，但是当工程非常大的时候，手写makefile也是非常麻烦的，如果换了个平台makefile又要重新修改，这时候就出现了下面的Cmake这个工具。

cmake就可以更加简单的生成makefile文件给上面那个make用。当然cmake还有其他更牛X功能，就是可以**跨平台**生成对应平台能用的makefile，我们就不用再自己去修改了。

可是cmake根据什么生成makefile呢？它又要根据一个叫CMakeLists.txt文件（学名：组态档）去生成makefile。

CMakeList.txt是需要我们自己手写的。

<img src="/images/compilelink/45.png" alt="45" style="zoom:80%;" />

nmake是Microsoft Visual Studio中的附带命令，需要安装VS，实际上可以说相当于linux的make

# 六、案例：使用 Make 构建网站

网站开发正变得越来越专业，涉及到各种各样的工具和流程，迫切需要构建自动化。

所谓"构建自动化"，就是指使用构建工具，自动实现"从源码到网页"的开发流程。这有利于提高开发效率、改善代码质量。

本文介绍如何使用make命令，作为网站的构建工具。以下内容既是make语法的实例，也是网站构建的实战教程。你完全可以将代码略作修改，拷贝到自己的项目。

## 6.1 Make的优点

首先解释一下，为什么要用Make。

目前，网站项目（尤其是Node.js项目）有三种构建方案。

> - 方案一：基于Node.js的专用构建工具（[Grunt](https://gruntjs.com/)、[Gulp](http://gulpjs.com/)、[Brunch](http://brunch.io/)、[Broccoli](https://github.com/broccolijs/broccoli)、[Mimosa](http://mimosa.io/)）
> - 方案二：npm run命令（[教程1](http://substack.net/task_automation_with_npm_run)、[2](http://blog.keithcirkel.co.uk/how-to-use-npm-as-a-build-tool/)、[3](http://gon.to/2015/02/26/gulp-is-awesome-but-do-we-really-need-it/)）
> - 方案三：make命令

我觉得，make是大型项目的首选方案。npm run可以认为是make的简化形式，只适用于简单项目，而Grunt、Gulp那样的工具，有很多问题。

**（1）插件问题**

Grunt和Gulp的操作，都由插件完成。即使是文件改名这样简单的任务，都要写插件，相当麻烦。而Make是直接调用命令行，根本不用担心找不到插件。

**（2）兼容性问题**

插件的版本，必须与Grunt和Gulp的版本匹配，还必须与对应的命令行程序匹配。比如，[grunt-contrib-jshint插件](https://github.com/gruntjs/grunt-contrib-jshint)现在是0.11.0版，对应Grunt 0.4.5版和JSHint 2.6.0版。万一Grunt和JSHint升级，而插件没有升级，就有可能出现兼容性问题。Make是直接调用JSHint，不存在这个问题。

**（3）语法问题**

Grunt和Gulp都有自己的语法，并不容易学，尤其是Grunt，语法很罗嗦，很难一眼看出来代码的意图。当然，make也不容易学，但它有复用性，学会了还可以用在其他场合。

**（4）功能问题**

make已经使用了几十年，全世界无数的大项目都用它构建，早就证明非常可靠，各种情况都有办法解决，前人累积的经验和资料也非常丰富。相比之下，Grunt和Gulp的历史都不长，使用范围有限，目前还没有出现它们能做、而make做不到的任务。

基于以上理由，我看好make。

## 6.2 常见的构建任务

下面是一些常见的网站构建任务。

- 检查语法
- 编译模板
- 转码
- 合并
- 压缩
- 测试
- 删除

这些任务用到 [JSHint](http://jshint.com/)、[handlebars](http://handlebarsjs.com/)、[CoffeeScript](http://coffeescript.org/)、[uglifyjs](http://lisperator.net/uglifyjs/)、[mocha](https://mochajs.org/) 等工具。对应的package.json文件如下。

```javascript
"devDependencies": {
 "coffee-script": "~1.9.1",
 "handlebars": "~3.0.0",
 "jshint": "^2.6.3",
 "mocha": "~2.2.1",
 "uglify-js": "~2.4.17"
}
```

我们来看看，Make 命令怎么完成这些构建任务。

## 6.3 Makefile的通用配置

开始构建之前，要编写Makefile文件。它是make命令的配置文件。所有任务的构建规则，都写在这个文件。

首先，写入两行通用配置。

```bash
PATH  := node_modules/.bin:$(PATH)
SHELL := /bin/bash
```

上面代码的PATH和SHELL都是BASH变量。它们被重新赋值。

PATH变量重新赋值为，优先在 node_modules/.bin 目录寻找命令。这是因为（当前项目的）node模块，会在 node_modules/.bin 目录设置一个符号链接。PATH变量指向这个目录以后，调用各种命令就不用写路径了。比如，调用JSHint，就不用写 ~/node_modules/.bin/jshint ，只写 jshint 就行了。

SHELL变量指定构建环境使用BASH。

## 6.4 检查语法错误

第一个任务是，检查源码有没有语法错误。

```bash
js_files = $(shell find ./lib -name '*.js')

lint: $(js_files)
 jshint $?
```

上面代码中，shell函数调用find命令，找出lib目录下所有js文件，保存在变量js_files。然后，就可以用jshint检查这些文件。

使用时调用下面的命令。

```bash
$ make lint
```

## 6.5 模板编译

第二个任务是编译模板。假定模板都在templates目录，需要编译为build目录下的templates.js文件。

```bash
build/templates.js: templates/*.handlebars
 mkdir -p $(dir $@)
 handlebars templates/*.handlebars > $@

template: build/templates.js
```

上面代码查看build目录是否存在，如果不存在就新建一个。dir函数用于取出构建目标的路径名（build），内置变量$@代表构建目标（build/templates.js）。

使用时调用下面的命令。

```bash
$ make template
```

## 6.6 Coffee脚本转码

第三个任务是，将CofferScript脚本转为JavaScript脚本。

```bash
source_files := $(wildcard lib/*.coffee)
build_files  := $(source_files:lib/%.coffee=build/%.js)

build/%.js: lib/%.coffee
 coffee -co $(dir $@) $<

coffee: $(build_files)
```

上面代码中，首先获取所有的Coffee脚本文件，存放在变量source*files，函数wildcard用来扩展通配符。然后，将变量source*files中的coffee文件名，替换成js文件名，即 lib/x.coffee 替换成 build/x.js 。

使用时调用下面的命令。

```bash
$ make coffee
```

## 6.7 合并文件

使用cat命令，合并多个文件。

```bash
JS_FILES := $(wildcard build/*.js)
OUTPUT := build/bundle.js

concat: $(JS_FILES)
 cat $^ > $(OUTPUT)
```

使用时调用下面的命令。

```bash
$ make concat
```

## 6.8 压缩JavaScript脚本

将所有JavaScript脚本，压缩为build目录下的app.js。

```bash
app_bundle := build/app.js

$(app_bundle): $(build_files) $(template_js)
 uglifyjs -cmo $@ $^

min: $(app_bundle)
```

使用时调用下面的命令。

```bash
$ make min
```

还有另一种写法，可以另行指定压缩工具。

```bash
UGLIFY ?= uglify

$(app_bundle): $(build_files) $(template_js)
 $(UGLIFY) -cmo $@ $^
```

上面代码将压缩工具uglify放在变量UGLIFY。注意，变量的赋值符是 ?= ，表示这个变量可以被命令行参数覆盖。

调用时这样写。

```bash
$ make UGLIFY=node_modules/.bin/jsmin min
```

上面代码，将jsmin命令给变量UGLIFY，压缩时就会使用jsmin命令。

## 6.9 删除临时文件

构建结束前，删除所有临时文件。

```bash
clean:
 rm -rf build
```

使用时调用下面的命令。

```bash
$ make clean
```

## 6.10 测试

假定测试工具是mocha，所有测试用例放在test目录下。

```bash
test: $(app_bundle) $(test_js)
 mocha
```

当脚本和测试用例都存在，上面代码就会执行mocha。

使用时调用下面的命令。

```bash
$ make test
```

## 6.11 多任务执行

构建过程需要一次性执行多个任务，可以指定一个多任务目标。

```bash
build: template concat min clean
```

上面代码将build指定为执行模板编译、文件合并、脚本压缩、删除临时文件四个任务。

使用时调用下面的命令。

```bash
$ make build
```

如果这行规则在Makefile的最前面，执行时可以省略目标名。

```bash
$ make
```

通常情况下，make一次执行一个任务。如果任务都是独立的，互相没有依赖关系，可以用参数 -j 指定同时执行多个任务。

```bash
$ make -j build
```

## 6.12 声明伪文件

最后，为了防止目标名与现有文件冲突，显式声明哪些目标是伪文件。

```bash
.PHONY: lint template coffee concat min test clean build
```

## 6.13 Makefile文件示例

下面是两个简单的Makefile文件，用来补充make命令的其他构建任务。

实例一。

```bash
PROJECT = "My Fancy Node.js project"

all: install test server

test: ;@echo "Testing ${PROJECT}....."; \
 export NODE_PATH=.; \
 ./node_modules/mocha/bin/mocha;

install: ;@echo "Installing ${PROJECT}....."; \
 npm install

update: ;@echo "Updating ${PROJECT}....."; \
 git pull --rebase; \
 npm install

clean : ;
 rm -rf node_modules

.PHONY: test server install clean update
```

实例二。

```bash
all: build-js build-css

build-js: 
browserify -t brfs src/app.js > site/app.js

build-css:
stylus src/style.styl > site/style.css

.PHONY build-js build-css
```

## 6.14 参考链接

- Jess Telford, [Example using Makefile for cloverfield](https://github.com/jesstelford/cloverfield-build-make)
- Oskar Schöldström, [How to use Makefiles in your web projects](http://oxy.fi/2013/02/03/how-to-use-makefiles-in-your-web-projects/)
- James Coglan, [Building JavaScript projects with Make](https://blog.jcoglan.com/2014/02/05/building-javascript-projects-with-make/)
- Rob Ashton, [The joy of make](http://codeofrob.com/entries/the-joy-of-make-at-jsconfeu.html)
