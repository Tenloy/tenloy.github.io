---
title: 使用Hexo+Github Pages搭建个人博客
date: 2021-04-10 10:25:24
tags:
  - hexo
---

## 一、Hexo配置和基本使用

### 1.1 概述

> Hexo 是一个快速、简洁且高效的博客框架。Hexo 使用 Markdown(或其他渲染引擎) 解析文章，在几秒内，即可利用靓丽的主题生成静态网页。

[hexo文档](https://hexo.io/zh-cn/docs/github-pages)

### 1.2 常用命令

#### 1.2.1 init

```bash
hexo init [folder] # 新建一个网站。如果没有设置folder，Hexo默认在目前的文件夹建立网站。
```

本命令相当于执行了以下几步：

1. Git clone [hexo-starter](https://github.com/hexojs/hexo-starter) 和 [hexo-theme-landscape](https://github.com/hexojs/hexo-theme-landscape) 主题到当前目录或指定目录。
2. 使用 [Yarn 1](https://classic.yarnpkg.com/lang/en/)、[pnpm](https://pnpm.js.org/) 或 [npm](https://docs.npmjs.com/cli/install) 包管理器下载依赖（如有已安装多个，则列在前面的优先）。npm 默认随 [Node.js](https://hexo.io/docs/#Install-Node-js) 安装。

#### 1.2.2 new

```bash
hexo new [layout] <title> # 新建一篇文章
```

- 如果没有设置 `layout` 的话，默认使用 [_config.yml](https://hexo.io/zh-cn/docs/configuration) 中的 `default_layout` 参数代替。
- 如果标题包含空格的话，请使用引号括起来。

| 参数              | 描述                                          |
| :---------------- | :-------------------------------------------- |
| `-p`, `--path`    | 自定义新文章的路径                            |
| `-r`, `--replace` | 如果存在同名文章，将其替换                    |
| `-s`, `--slug`    | 文章的 Slug，作为新文章的文件名和发布后的 URL |

默认情况下，Hexo 会使用文章的标题来决定文章文件的路径。对于独立页面来说，Hexo 会创建一个以标题为名字的目录，并在目录中放置一个 `index.md` 文件。你可以使用 `--path` 参数来覆盖上述行为、自行决定文件的目录：

```bash
hexo new page --path about/me "About me"
# 以上命令会创建一个 `source/about/me.md` 文件，同时 Front Matter 中的 title 为 `"About me"`

# 注意！title 是必须指定的！如果你这么做并不能达到你的目的：
hexo new page --path about/me
# 此时 Hexo 会创建 `source/_posts/about/me.md`，同时 `me.md` 的 Front Matter 中的 title 为 `"page"`。这是因为在上述命令中，hexo-cli 将 `page` 视为指定文章的标题、并采用默认的 `layout`。
```

#### 1.2.3 generate

```bash
hexo generate  # 生成静态文件。可以简写为hexo g
```

| 选项                  | 描述                                                         |
| :-------------------- | :----------------------------------------------------------- |
| `-d`, `--deploy`      | 文件生成后立即部署网站。`hexo g -d` 与 `hexo d -g` 两个命令的作用是相同的。 |
| `-w`, `--watch`       | 监视文件变动。Hexo 能够监视文件变动并立即重新生成静态文件，在生成时会比对文件的 SHA1 checksum，只有变动的文件才会写入。 |
| `-b`, `--bail`        | 生成过程中如果发生任何未处理的异常则抛出异常                 |
| `-f`, `--force`       | 强制重新生成文件 Hexo 引入了差分机制，如果 `public` 目录存在，那么 `hexo g` 只会重新生成改动的文件。 使用该参数的效果接近 `hexo clean && hexo generate` |
| `-c`, `--concurrency` | 最大同时生成文件的数量，默认无限制                           |

#### 1.2.4 deploy

```bash
hexo deploy # 部署网站。可以简写为：hexo d
```

| 参数               | 描述                     |
| :----------------- | :----------------------- |
| `-g`, `--generate` | 部署之前预先生成静态文件 |

#### 1.2.5 server

```bash
hexo server  # 启动服务器。可以简写为：hexo s
```

默认情况下，访问网址为： `http://localhost:4000/`。

| 选项             | 描述                           |
| :--------------- | :----------------------------- |
| `-p`, `--port`   | 重设端口                       |
| `-s`, `--static` | 只使用静态文件                 |
| `-l`, `--log`    | 启动日记记录，使用覆盖记录格式 |

#### 1.2.6 clean

```bash
hexo clean  # 清除缓存文件 (`db.json`) 和已生成的静态文件 (`public`)。
```

在某些情况（尤其是更换主题后），如果发现您对站点的更改无论如何也不生效，您可能需要运行该命令。

#### 1.2.7 其他

```bash
hexo publish [layout] <filename> # 发表草稿
hexo render <file1> [file2] ... # 渲染文件。可通过参数-o,--output来设置输出路径
hexo migrate <type> # 从其他博客系统 迁移内容 https://hexo.io/zh-cn/docs/migration
hexo list <type>  #列出网站资料
hexo version  # 显示 Hexo 版本
```



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

- 上传content字段之后，可能会因为某条内容的索引数据太大而报错。那只能对该条内容的`content`字段进行屏蔽

  ```shell
  AlgoliaSearchError: Record at the position 0 objectID=d8676bd7611266ed2404ee6cee119d4a4a911cb0 is too big size=12920 bytes. Contact us if you need an extended quota
      at success (D:\metang326.github.io\node_modules\hexo-algolia\node_modules\algoliasearch\src\AlgoliaSearchCore.js:375:32)
      at process._tickCallback (node.js:369:9)
  ```

  ```js
  // node_modules/hexo-algolia/lib/command.js 添加代码
  
  return publishedPagesAndPosts.map(function(data) {
          var storedPost = _.pick(data, [
            'title',
            'date',
            'slug',
            'content',
            'excerpt',
            'permalink',
            'layout'
          ]);
  // 添加判断，对指定的文章删除content字段
          if (typeof storedPost.permalink === "string" &&
              storedPost.permalink.indexOf("10_Web-Module") != -1) {
            storedPost = _.pick(data, [
              'title',
              'date',
              'slug',
              'excerpt',
              'permalink',
              'layout'
            ]);
          }
  }
  ```



algolia网站配置步骤[参考链接](https://blog.csdn.net/qq_35479468/article/details/107335663)



## 五、评论系统配置

https://www.heson10.com/posts/3217.html

https://blog.shuiba.co/comment-systems-recommendation

gitalk



## 附：GitBook的使用注意点

### 6.1 不支持本地导出HTML

新版本不支持本地导出的HTML跳转，解决方案：

- 在_book文件夹中找到gitbook->theme.js文件。
- 在代码中搜索 `if(m)for(n.handler&&`

- 将`if(m)`改成`if(false)`，再重新打开index.html即可 

缺点：每次都会重置侧边栏。如果是部署后访问，侧边栏点击跳转后，不会重置状态



### 6.2 默认主题运行报错

在使用该主题的过程中，发现经常会在控制台报下面的错误，没有找到是哪里的原因，官方也一直没有修复。

```
theme.js:4UncaughtTypeError:Cannot read property'split' of undefined
```

后来在 [这里](https://github.com/maxkoryukov/theme-default/commit/811fcca17fcc84ad9ff3f940a4194dbffa62a31d) 看到一个解决方法，需要修改本地的 GitBook Theme 模板。下面是具体步骤：

- 进入 GitBook 默认主题所在的文件夹 `用户主目录` -> `.gitbook` -> `versions` -> `3.2.2` -> `node_modules` -> `gitbook-plugin-theme-default` -> `src` -> `js` -> `theme`，打开 `navigation.js`，找到 `getChapterHash` 函数

  ```javascript
  function getChapterHash($chapter){
    var $link = $chapter.children('a'),      
        hash = $link.attr('href').split('#')[1];
    
    if(hash) hash ='#'+hash;
    return(!!hash)? hash :'';
  }
  ```

- 将该函数修改为下面的形式:

  ```javascript
  function getChapterHash($chapter){
    var $link = $chapter.children('a'),      
        hash,      
        href,      
        parts;
    if($link.length){      
      href = $link.attr('href')
      if(href){          
        parts = href.split('#');
        if(parts.length>1){              
          hash = parts[1];
        }
      }
    }
    if(hash) hash ='#'+hash;
    return(!!hash)? hash :'';
  }
  ```

- 回到 `gitbook-plugin-theme-default` 文件夹，运行 `npm install` 重新编译文件。



### 6.3 `anchor-navigation-ex`插件回到顶部

- 如果文章有1级标题就必定好使
- 如果没有就：第一次好使，之后不好使。锚点设置的有问题