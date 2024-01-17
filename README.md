## Function

* 支持若干 ALU 指令，但 valu 目前不能处理 vl 不为整倍数的情况（即每个 lane 分到的要处理数据必须是 VRFWordWidth 的倍数）
* 支持 VLE, VSE 指令，并且支持 vl 不为整倍数的情况，但要求 scalar cpu 将 vl 补到整倍数（即 scalar cpu 需要发送或接收整倍数的 operand）。

## TODO List

* 处理指令访问的数据总数不是 8*NrLane Bytes 的倍数的情况
* 同步各个 lane 的 done 信号
* **在 `vinsn_launcher` 中增加冒险，依赖检测**
* 增加标量寄存器的传输接口（在 rvv1.0 中，只有 vsetvl，vlse, vsse 三种指令会用到两个标量寄存器，但在目前的设计考虑中这三种指令都应该在 scalar cpu 中完成），并实现相应的传输指令。
* 处理 flush_i 信号
* 如何处理其他 IP 的依赖？
* 重命名握手信号，根据握手方式，使用下面两种命名方式：
    * valid <-> grant 握手信号，grant 信号依赖于 valid 信号，只有当 valid 信号拉高时 grant 信号才可能拉高
    * valid <-> ready 握手信号，ready 可以独立于 valid 信号拉高，但也可以依赖于 valid ?

  注意：valid, ready 信号一旦拉高，直到握手成功才能拉低

* 目前 memory 接口中一个未处理的问题是 mask load/store 指令中 mask 的传递，在 ara 中 masked load 也会产生 memory 访问。从 rvv1.0 的 section 9 看起来这是允许的，因为 mask 是作为 control dependency。只是 masked load 不允许产生异常。

## Design

* 目前的握手信号处理感觉有些混乱，valid, ready 信号之间的依赖关系从命名上看得不够清楚
    * decoder <-> scalar core, decoder 会在下一级流水线能动（即 launcher 拉高了自己的 ready 或者 下一级寄存器不存在有效信号）时将 ready 信号拉高，因此 decoder 的 ready 信号与 scalar core 无关
    * launcher <-> decoder, decoder 的 req_valid 信号从流水线寄存器中发出，因此显然是与 launcher 的 ready 信号无关，而 launcher 的 ready 信号的生成逻辑与 decoder 一致，仅依赖于下一级（vrf_accesser 和 vfu）的 ready 信号
    * vrf_accesser <-> launcher, vrf_accesser 中每个 opqueue 的 ready 信号独立拉高，当 op_req_i 中请求的 opqueue 都 ready 时，vrf_accesser 的 ready 信号会拉高，因此总的说来，vrf_accesser 的 ready 信号不依赖于 launcher 的 valid 信号。但由于 lanes.sv 中整合了每个 lane 的信号，导致每个 vrf_accesser 收到的 valid 的信号是依赖于自身发出的 ready 信号的（当所有 lane 的 vrf_accesser 的 ready 拉高时，vrf_accesser 才可能收到拉高的 valid 信号）
    * vfu <-> launcher, vfu 当自己的 state 为 IDLE 时，拉高 ready 信号，因此 ready 信号与 launcher 的 valid 信号无关，由于与 vrf_accesser 同样的原因，vfu 收到的 valid 信号依赖于自己发出的 ready 信号

## Ideas

* 使用 micro op 来简化设计？
* 增加 memory interface 的带宽？每周期能取出的操作数应与 memory 的带宽相匹配
* rvv 中 shuffle 的来源：
    * 指令需要的源操作数和实际的源操作数排布不匹配
    * slide 相关指令
    * reduce 相关指令
    * memory 相关指令

  后两类因为 dst_sew == src_sew，几乎可以用移位实现，我们称为 quick shuffle。而第一类情况很少见，可以给一个很慢的实现，称为 slow shuffle。memory 指令需要处理 memory layout 和 register layout 之间的差异，我们称为 mem shuffle，这个怎么处理比较好呢？

* 支持 EW1：
    * 优点：涉及 mask 的指令都不需要 shuffle 了，包括指令用到的 mask bits，以及指令产生的 mask bits
    * 缺点：shuffle 代价变大，shuffle 的粒度从 byte 变成 bit，虽然这可以一定程度的缓解，例如令 quick shuffle    中不支持 EW1，需要处理时发射 micro op 走一遍 slow shuffle 路径。但 mem shuffle 不是很好处理，因为 ISA 层    提供了 vlm, vsm 指令。
    * 另外 mem shuffle 除了操作数，还涉及到 mask，这应该不会带来额外的开销，仅仅是从 EW8 排布的 shuffle 换成 EW1 而已。

* 尽可能地让各个 lane 同步可以简化设计，目前的想法是：将 vstart 和 vl 与 lane 的数目对齐，然后利用 mask 将多余的计算舍弃掉。
* 实现一些 log helper

## Non-speculative branch

* Only non-speculative instruction can be sent to this core.
* `flush_i` signal is only used to flush interrupted memory instruction.
* Decoder will assert `done` in the same cycle of receiving rvv inst, except VWXUNARY0, VWFUNARY0 and floating instructions. These instructions will return 64bits data or fflags to scalar cpu.
