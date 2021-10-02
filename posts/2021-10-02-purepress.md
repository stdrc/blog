---
title: 关于静态博客生成器的一点感想
categories: Misc
tags: [Blog, Octopress, BlogA, VeriPress, PurePress]
created: 2021-10-02 19:56:00
---

从高中刚开始尝试搭建自己的博客，就是采用了静态博客的思路，即使用 Markdown 编写博文，然后用一个静态博客生成器将 Markdown 转换成 HTML，之后使用静态文件服务器部署。与之相对应的是 WordPress 的思路，即动态运行一个网站后端，在请求到来时从文件或数据库加载博文，生成 HTML 返回。

最开始使用的静态博客生成器是 [Octopress](http://octopress.org)，是基于 [Jekyll](https://jekyllrb.com) 的，后者是 GitHub Pages 使用的默认静态博客生成器。用 Octopress 搭建博客的过程，也是不断学习许多新玩意的过程，比如 Git、常用的 Shell 命令、自定义域名等。

后来学了 Python，想着用这个语言做点什么有用的东西，于是写了自己的静态博客生成器 [BlogA](https://github.com/verilab/blog-a)，再到后来的 [VeriPress](https://github.com/verilab/veripress) 和最新的 [PurePress](https://github.com/verilab/purepress)。这段过程在去年已经在我的 Telegram 频道 [Channel RC](https://t.me/channel_rc) 发过总结，摘录如下：

> 折腾静态博客生成器很久了，从刚开始学 Python 时候写的 BlogA，到后来重写的「功能看起来更丰富」的 VeriPress，基本满足了自己对一个博客生成器的需求。可是渐渐地，越来越觉得不太对，写 VeriPress 时试图让它变得可扩展，结果导致做了许多对我的需求没有帮助的抽象，代码变得看似解耦实则混乱，最终完全没有动力维护了。
>
> 于是前些时间决定再重来一次，对 VeriPress 做一个充分的精简，只保留自己真正需要的功能，尝试用最少的代码实现完美符合自己需求的博客生成器。经过好几次的忙里偷闲，终于写完了，命名为 PurePress。项目的核心 Python 代码只有两个文件，一个是 `__init__.py`，330 行，用来实现博客的 preview 功能，包括文章的加载、Flask 的路由等，另一个是 `__main__.py`，260 行，用来实现命令行工具和 build 功能。
>
> PurePress 的一切都是基于我对静态博客生成器的使用习惯，不多不少，代码里没有一句废话（希望真的如此），实在是让人感到舒适。

经过一年的使用和小修小补，PurePress 仍然保持了初心，目前仅 672 行代码（包括空行和注释），只包含我真正需要的功能，即你在本博客网站及 [GitHub 仓库](https://github.com/richardchien/blog) 源码中能看到的功能。我想这些功能应该足够支撑大部分人写博客了。

到了最近，又渐渐感觉先前的博客主题 [Light](https://github.com/verilab/purepress-theme-light) 太过花哨，**博客的主要关注点应该是它的内容，而不是外观**。于是又重新写了一个 PurePress 主题（参考了 [这个博客](https://steveklabnik.com)），叫做 [Minimal](https://github.com/verilab/purepress-theme-minimal)，采用了极简的样式，以凸显内容为目标，减少主题样式本身的喧兵夺主，最终效果还不错。

目前看来，PurePress 本身的功能和对主题的支持经过了一年多的考验还算不错。打算在之后有空的时候补一下文档，让更多对其有兴趣的人可以方便地用它搭建静态博客。

而自己的这个博客在换用 Minimal 主题之后，也将把重心放在输出更优质更有干货的内容上，而不只是让它看起来好看。
