---
title: 使用Hexo+Github Pages搭建个人博客
date: 2021-04-10 10:25:24
tags:
  - hexo
---

## 一、Hexo配置

> Hexo 是一个快速、简洁且高效的博客框架。Hexo 使用 Markdown(或其他渲染引擎) 解析文章，在几秒内，即可利用靓丽的主题生成静态网页。

[hexo文档](https://hexo.io/zh-cn/docs/github-pages)



## 二、主题配置

[fork的theme](https://github.com/Tenloy/hexo-theme-archer)

根据喜好随便改：配置简书、RSS

**GIT**子模块：

- 现在我们的Blog项目受GitHub管理，是个仓库，其中包含了一个主题仓库。其中对主题仓库的修改，要在外层仓库、theme仓库分别提交一次
- Git 通过子模块来解决这个问题。 子模块允许你将一个 Git 仓库作为另一个 Git 仓库的子目录。 它能让你将另一个仓库克隆到自己的项目中，同时还保持提交的独立。 [Git-子模块](https://git-scm.com/book/zh/v2/Git-工具-子模块)

## 三、Travis CI配置

持续集成（Continuous integration，简称CI）

可以在其中加入一些自动化命令的执行，如每次commit，自动hexo algolia、hexo clean && hexo g && hexo s

[参考链接](https://mfrank2016.github.io/breeze-blog/2020/05/02/hexo/hexo-start/#toc-heading-12)

但并没有以下问题：

> 注意：有两种类型的 `github pages`，一种是使用 `用户名.github.io` 作为项目名，一种是使用其它名称。虽然看起来只是名字不一样，但两种方式其实是有差异的，前一种方式里，网页静态文件只能存放在 master 分支，所以如果想要把博客源文件也存到同一个仓库，必须使用其它分支来存放，相应的 travis ci 监听和推送的分支也需要修改，当然也可以使用另一个新的仓库来存放。后一种方式则没这个限制，通常使用名为 `gh-pages` 作为分支名，`Hexo` 内默认设置的分支也是叫这个名字。这里我们使用的是后一种方案，即源文件和生成的网页静态文件存放在同一个仓库，源文件在 `master` 分支，静态文件在 `gh-pages` 分支。



## 四、algolia站内搜索配置

algolia网站本质上就是提供了数据库，提供了接口给使用者，供其将要被检索的内容上传。

hexo-algolia工具就是完成了文档中内容的摘取，然后上传，上传的各项内容，其key就相当于数据库的表字段。

- hexo-algolia 要1.2.2版本之前，之后去掉了content字段，即表中不存储文章内容，所以不能搜索文章内容

algolia网站配置步骤[参考链接](https://blog.csdn.net/qq_35479468/article/details/107335663)



## 五、评论系统配置

https://www.heson10.com/posts/3217.html

https://blog.shuiba.co/comment-systems-recommendation

gitalk





TODO：把搜索移出来