---
title: CI-CD
date: 2021-04-12 14:59:20
tags:
  - CI/CD
categories:
  - 软件工程(化)
---

## 一、常见的Travis CI与Jenkins

[参考链接：谁才是世界上最好的 CI/CD 工具？](https://zhuanlan.zhihu.com/p/67805669)

**On-Premise vs Hosted**

- On-Premise 需要用户搭建自己的服务器来运行 CI/CD 工具。
- Hosted CI/CD 工具是一个 SaaS 服务，不需要用户搭建自己的服务器。

常见的 CI/CD 工具

- TeamCity 和 Jenkins 属于 “On-Premise” 阵营

- Travis CI 属于 “Hosted” 阵营

- AppVeyor 和 Azure Pipelines 则是既能 “On-Premise” 又能 “Hosted” 

如果在 CI/CD 过程中，需要连接到不同的内网服务。那么 On-Premise 的 CI/CD 工具适合这样的使用场景，你可以把 Build Agent 部署在内网的机器上，这样可以轻松地连接内网资源。

如果你不需要连接内网资源，那么 Hosted CI/CD Service 就是你的最佳选择了，有以下几个优势：

- 维护成本：Hosted CI/CD Service 可以说是零维护成本了，整个运行环境都由服务商托管。相比于 On-Premise 的CI/CD 工具，使用者需要自己花大量时间搭建与维护服务器，对于 Hosted CI/CD Service 来说，使用者完全不需要担心背后服务器的维护。
- Clean的运行环境：假设你在为你的 Python 项目寻求一个 CI/CD 工具，而你的 Python 项目需要同时对 Python 2.7, 3.6, 3.7 进行持续集成，那么 Hosted CI/CD Service 完全可以满足你的需要。On-Premise 的机器上，你需要对不同的 Python 版本而烦恼，而 Hosted CI/CD Service 每次都会创建一个新的运行环境，想用哪个 Python 版本就用哪个。
- 预装的软件和运行时：每一个项目在做持续集成时，往往会需要依赖不同的运行时和工具链，Hosted CI/CD Service 会帮你预装好许多常用的软件和运行时，大大减少了搭建环境的时间。
- 价格：价格成本也是我们在技术选型要重点考虑的一点。
  - On-Premise 的 TeamCity 和 Jenkins：虽然他们都是免费使用的，但是使用者都需要搭建自己的服务器，不论是用自己的物理机还是使用 Azure 或是 AWS 上的虚拟机，这都是一个花费。特别是对于大规模的持续集成的需求下，这会是个很大的价格成本。
  - 对于开源项目，Hosted CI/CD Service 有着很大的优势，Travis CI、AppVeyor 和 Azure Pipelines 对于开源项目都是完全免费的。
  - 对于私有项目，Travis CI 和 AppVeyor 是收费的，而 Azure Pipelines 有一个月 1800 分钟的免费额度。可见，对于私有项目，Azure Pipelines 有很大的优势。