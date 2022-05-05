---
title: Protocol Buffer的基本介绍
date: 2021-06-25 17:48:19
urlname: Protocol-Buffer.html
tags:
categories:
  - 数据的传输与存储
---

## 一、概述

Protocol buffers (PB) 是一种语言、平台无关，可扩展的序列化数据的格式。和xml、json等数据交换格式一样，也可用于通信协议，数据存储等。

- Protocol buffers 在序列化数据方面，它是**灵活的**，**高效的**(快)。
  - Portobuf序列化和反序列化速度比XML、JSON快很多，是直接把对象和字节数组做转换，而XML和JSON还需要构建成XML或者JSON对象结构。
  - 一旦定义了要处理的数据的数据结构之后，就可以利用 Protocol buffers 的代码生成工具生成相关的代码。甚至可以在无需重新部署程序的情况下更新数据结构。只需使用 Protobuf 对数据结构进行一次描述，即可利用各种不同语言或从各种不同数据流中对你的结构化数据轻松读写。
- 相比于 XML、JSON 来说，Protocol buffers 更加**小巧**，更加**简单**。
  - XML和JSON的描述信息太多了，导致消息要大；
  - 此外Portobuf还使用了Varint 编码，减少数据对空间的占用。

**Protocol buffers 很适合做数据存储或 RPC 数据交换格式。可用于通讯协议、数据存储等领域的语言无关、平台无关、可扩展的序列化结构数据格式**。

Protobuf支持生成代码的语言包括Java、Python、C++、Go、JavaNano、Ruby、C#，[官网地址](https://link.jianshu.com?t=https://developers.google.com/protocol-buffers/)。

### 1.1 优势

JSON 和 XML 可能是目前开发者们用来存储和传输数据的标准方案，而 protocol buffers 与之相比有以下优势：

- **快速且小巧**：按照 Google 所描述的，protocol buffers 的体积要小**3-10**倍，速度比XML要快**20-100**倍。可以在这篇[文章](https://damienbod.com/2014/01/09/comparing-protobuf-json-bson-xml-with-net-for-file-streams/) ，它的作者是 Damien Bod，文中比较了一些主流文本格式的读写速度。
- **类型安全**：Protocol buffers 像 Swift 一样是类型安全的，使用 protocol buffers 时 你需要指定每一个属性的类型。
- **自动反序列化**：你不需要再去编写任何的解析代码，只需要更新 **.proto** 文件就行了。 file and regenerate the data access classes.
- **分享就是关心**：因为支持多种语言，因此可以在不同的平台中共享数据模型，这意味着跨平台的工作会更轻松。

### 1.2 局限性

Protocol buffers 虽然有着诸多优势，但是它也不是万能的:

- **时间成本**：在老项目中去使用 protocol buffers 可能会不太高效，因为需要转换成本。同时，项目成员还需要去学习一种新的语法。
- **可读性**：XML 和 JSON 的描述性更好，并且易于阅读。Protocol buffers 的原数据无法阅读(类似txt没有样式，不方便阅读)，并且在没有 **.proto** 文件的情况下没办法解析。
- **仅仅是不适合而已**：当你想要使用类似于[XSLT](http://www.w3schools.com/xml/xml_xslt.asp)这样的样式表时，XML是最好的选择。所以 protocol buffers 并不总是最佳工具。
- **不支持**：编译器可能不支持你正在进行中的项目所使用的语言和平台。

## 二、iOS中的单独使用

### 2.1 定义.proto文件

首先要定义一个 Person**.proto** 文件。在这个文件中指定了你的数据结构信息。下面以一个Person模型类为例

```protobuf
// proto语法
syntax = "proto3";  // 在第一行声明，我们使用的protobuf语法是proto3

message Person {
  string name = 1;
  int32 uid = 2;
  string email = 3;
  enum PhoneType {
    MOBILE = 0;
    HOME = 1;
    WORK = 2;
  }
  message PhoneNumber {
    string number = 1;
    PhoneType type = 2;
  }
   repeated PhoneNumber phone = 4;
}
```

### 2.2 转换为源代码文件

使用 protocol buffers 的编译器，会根据选择的语言创建好一个数据类(Swift 中的 struct)。可以直接在项目中使用这个类/结构。

```bash
protoc *.proto --objc_out=../Class  # objc_out指定了生成程序的目录，如果是Java，那么是java_out
# 产物是：
# Class/Pro_out/Person.pbobjc.h  Person.pbobjc.m
# Class/Pro_source/Person.proto
```

### 2.3 iOS工程中引入Protobuf库

- 通过Cocoapods
- 通过手动导入

### 2.4 使用

```objc
// 导入头文件
#import "Person.pbobjc.h"

// 创建对象
Person *person = [Person new];
person.name = @"weiCL";
person.uid = 20170810;
person.email = @"cl9000@126.com";

// 序列化为Data
NSData *data = [person data];
NSLog(@"NSData= %@", data);

// 反序列化为对象
Person *person2 = [Person parseFromData:data error:NULL];
NSLog(@"name:%@ uid:%d email:%@",person2.name,person2.uid,person2.email);
```

## 三、用在与服务端交互中

在与服务端交互时，通常使用 JSON 或者 XML 来发送和接收数据，然后根据这些数据生成结构并解析。现在使用 `protocol buffers` 也类似：

- 服务端返回的数据要为pb格式
- 移动端使用pb数据的解析配置

参考链接：[Protocol Buffers 在 iOS 中的使用](https://juejin.cn/post/6844903622266847246)

## 四、编码原理(序列化与反序列化)

```
可读数据 ====序列化、字符集编码规则===> 二进制
可读数据 <===反序列化、字符集编码规则==== 二进制
```

### 4.1 编码/序列化

- Protocol Buffer 序列化采用 Varint、Zigzag 方法，压缩 int 型整数和带符号的整数。对浮点型数字不做压缩（这里可以进一步的压缩，Protocol Buffer 还有提升空间）。
- 对 `.proto` 文件，会对 option 和 repeated 字段进行检查，若 optional 或 repeated 字段没有被设置字段值，那么该字段在序列化时的数据中是完全不存在的，即不进行序列化（少编码一个字段）。

- 上面这两点做到了压缩数据，使得序列化工作量减少。

- Protocol Buffer 是 Tag - Value (TLV)的编码方式的实现

  - > 在通信协议中，TLV（type-length-value或tag-length-value）是一种用于某种协议中可选信息元素的编码方案。TLV 编码的数据流包含记录类型的代码，然后是记录值长度，最后是值本身。

  - 数据都以 tag - length - value (或者 tag - value)的形式存在二进制数据流中
  - 减少了分隔符的使用（比 JSON 和 XML 少了 `{ } :` 这些符号）
  - 没有这些分隔符，使得数据存储更加紧凑，也算是再一次减少了数据的体积。

- 综上，pb 体积相对较小，如果选用它作为网络数据传输，势必相同数据，消耗的网络流量更少。

### 4.2 反序列化

- 反序列化的实现完全是序列化实现/encode的逆过程。反序列化直接读取二进制字节数据流，同样是一些二进制操作。
- 反序列化的时候，通常只需要用到 length。tag 值只是用来标识类型的，Properties 的 setEncAndDec() 方法里面已经把每个类型对应的 decode 解码器初始化好了，所以反序列化的时候，tag 值可以直接跳过，从 length 开始处理。
- XML 的解析过程就复杂一些。XML 需要从文件中读取出字符串，再转换为 XML 文档对象结构模型。之后，再从 XML 文档对象结构模型中读取指定节点的字符串，最后再将这个字符串转换成指定类型的变量。这个过程非常复杂，其中将 XML 文件转换为文档对象结构模型的过程通常需要完成词法文法分析等大量消耗 CPU 的复杂计算。

### 4.3 性能

- 如果很少用到整型数字，浮点型数字，全部都是字符串数据，那么 JSON 和 protocol buffers 性能不会差太多。纯前端之间交互的话，选择 JSON 或者 protocol buffers 差别不是很大。

- 与后端交互过程中，用到 protocol buffers 比较多，笔者认为选择 protocol buffers 除了性能强以外，完美兼容 RPC 调用也是一个重要因素。

### 4.4 其它特性

1. Protocol Buffer 另外一个核心价值在于提供了一套工具，一个编译工具，自动化生成 get/set 代码。简化了多语言交互的复杂度，使得编码解码工作有了生产力。
2. Protocol Buffer 不是自我描述的，离开了数据描述 `.proto` 文件，就无法理解二进制数据流。这点即是优点，使数据具有一定的“加密性”，也是缺点，数据可读性极差。所以 Protocol Buffer 非常适合内部服务之间 RPC 调用和传递数据。
3. Protocol Buffer 具有向后兼容的特性，更新数据结构以后，老版本依旧可以兼容，这也是 Protocol Buffer 诞生之初被寄予解决的问题。因为编译器对不识别的新增字段会跳过不处理。

参考链接：[高效的数据压缩编码方式 Protobuf — halfrost](https://halfrost.com/protobuf_encode/)、[Protobuf的序列化/反序列化](https://halfrost.com/protobuf_decode/)

