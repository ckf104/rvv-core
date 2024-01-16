## Function

* 支持若干 ALU 指令，但 valu 目前不能处理 vl 不为整倍数的情况（即每个 lane 分到的要处理数据必须是 VRFWordWidth 的倍数）
* 支持 VLE, VSE 指令，并且支持 vl 不为整倍数的情况，但要求 scalar cpu 将 vl 补到整倍数（即 scalar cpu 需要发送或接收整倍数的 operand）。

## TODO List

* ~~没有对多提交的问题进行处理，一个周期内如果完成了多条指令（多个vfu的情况下），但是目前接口每周期只能提交一条指令，需要考虑将 vfu 进行 stall？~~
* 处理指令访问的数据总数不是 8*NrLane Bytes 的倍数的情况
* ~~目前没有整合多条 lane 的信号，因此只支持单条 lane~~。
* **在 `vinsn_launcher` 中增加冒险，依赖检测**
* ~~增加 vector load 指令对应的 operand 接口~~
* ~~支持EW8，EW16，EW32版本的 vector store 指令~~
* ~~支持EW8，EW16，EW32版本的 vector load 指令~~
* 如何处理其他 IP 的依赖？

## Ideas

* 使用 micro op 来简化设计？
