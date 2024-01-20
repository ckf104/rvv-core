## Function

* 支持若干 ALU 指令，并且 ALU 支持非对齐的 vl, vstart
* 支持 VLE, VSE 指令，支持非对齐的 vl，vstart。对于非对齐的 vl, vstart，要求 scalar cpu 发送时对齐 VRFWordWidth（目前 VRFWordWidth == 64，例如 vstart = 6, EW = 32 时，scalar cpu 对齐到 vstart = 4 时发送，第一个 word 的前 32bits 会被 rvvcore 丢弃）
* 目前的冒险处理非常简单：当遭遇 WAR, RAW, WAW 时暂停发射

## TODO List

* 同步各个 lane 的 done 信号
* vlu, vsu 支持 vstart
* 支持 mask, EW1
* 支持 widening, narrowing 指令
* 目前的 load/store 接口是否友好？当地址未对齐时是否造成一些问题（例如 vstart = 1, EW = 32, 目前的接口要求强制对齐到 vstart == 0, 如果 vstart == 1 时地址才 8Bytes 对齐，这会导致每次访问的对齐降级为 4Bytes）
* Use x to replace default zero
* 将需要 reset 和不需要 reset 的寄存器的 always_ff 区分开
* Support NrLane=1: 主要是有些地方应该使用 GetWidth(NrLane) 的，误用了 LogNrLane，以及有些信号如果 NrLane=1 时就宽度为 0 了
* chaining support
* 增加标量寄存器的传输接口（在 rvv1.0 中，只有 vsetvl，vlse, vsse 三种指令会用到两个标量寄存器，但在目前的设计考虑中这三种指令都应该在 scalar cpu 中完成），并实现相应的传输指令。
* 处理 flush_i 信号
* 如何处理其他 IP 的依赖？
* 重命名握手信号，根据握手方式，使用下面两种命名方式：
  * valid <-> grant 握手信号，grant 信号依赖于 valid 信号，只有当 valid 信号拉高时 grant 信号才可能拉高
  * valid <-> ready 握手信号，ready 可以独立于 valid 信号拉高，但也可以依赖于 valid ?

  注意：valid, ready 信号一旦拉高，直到握手成功才能拉低

* 目前 memory 接口中一个未处理的问题是 mask load/store 指令中 mask 的传递，在 ara 中 masked load 也会产生 memory 访问。从 rvv1.0 的 section 9 看起来这是允许的，因为 mask 是作为 control dependency。只是 masked load 不允许产生异常。

* 如何处理 flush（这里的 flush 是针对 non-speculative branch 中发生内存翻译异常的处理）？主要的困难来源于 vector load/store 发生异常时，如何 flush 掉多余的 load/store operand 等。牵扯到向量指令什么时候提交，存在一些利弊权衡。
  * 讨论的假定是我们认为异常发生时仅 flush 掉发生异常的 vector load/store 指令是困难的，对于 vector store，如何恰好地将已经从 vrf 中取出的，并且编号在发生异常的 op 后的 store op/index 清除掉，对于 vector load 有类似的讨论。若假定成立，我们需要在 flush 时清空整个 rvvcore。
  * 如果我们选择尽可能早地提交掉向量指令，那么 flush 信号来临时我们并不能马上应答，因为还有许多向量指令仍在执行。我能想到两种解决方案，一种是 rvvcore 提供一个 gnt 信号，要求 scalar cpu 等待 gnt 信号拉高后才认为 flush 完成。或者我们在 rvvcore 内部暂时将 flush 信号用一个寄存器存储起来，当该寄存器的 flush 信号拉高时，拉低 rvvcore 的 ready 信号。
  * 如果我们选择在向量指令完成后再提交给 scalar cpu，那么还有第三种方法来处理 flush 信号，即将责任转交给 scalar cpu，cpu 等待所有在异常指令之前的指令完成后，再拉高 flush 指令，此时 rvvcore 只需要在 flush 拉高后将整个 core 内部的状态重置即可。

* 如何处理读写冒险，以及实现 chaining?
  * 首先约定这里关于 chaining 的目标，我们只希望实现 RAW chaining。因为 WAW 与 WAR 冒险可以通过增加物理寄存器，进行重命名来避免，因此它们对应的 chaining 暂时不考虑。
  * 关于 scalar cpu 中冒险处理的 scoreboard 的实现可以参考 [记分牌ScoreBoard](https://zhuanlan.zhihu.com/p/496078836)，概括来看，我们认为经典 scoreboard 的实现为
    * 每个寄存器使用 1 bit 来标记该寄存器是否会被某条已发射的指令写。
    * 如果待发射的指令需要读取的寄存器对应的 1 bit 被拉高，则 stall，规避 RAW 冒险。
    * 如果待发射的指令需要写回的寄存器对应的 1 bit 被拉高，则 stall，规避 WAW 冒险。
    * 我们不需要考虑 WAR 冒险，因为通常指令在发射时就会读取所有需要的寄存器，因此在指令写回时，它前面的指令一定都已经完成了读寄存器的操作。
    * 一种可能想到的优化是在指令写回时才读取计分板，考虑 WAW 冒险，在发射时仅考虑 RAW 冒险。但这会存在一些问题，例如两条写同一个寄存器的指令都发射了，那么首先我们需要一些机制来判断这两条指令的发射顺序，避免后发射的指令先提交写回，导致最终先发射的指令将后发射的指令的结果覆盖了。其次，使用 1 bit 来标记寄存器就不够了，我们需要一个多 bit 的 counter 来对将写该寄存器的指令计数。每有一条指令写回该寄存器，计数减一，计数归零时才能发射需要读该寄存器的指令。总之，将 WAW 冒险的判断移到写回阶段是可行的，但是会复杂化计分板的设计。

  * 现在我们回来看 rvvcore 处理读写冒险时会遇到哪些额外的难题。
    * 首先是我们需要考虑 WAR 冒险了。因为向量指令不能在发射阶段就读取完所有的操作数。这意味这件事，首先我们需要额外标记该寄存器是否被某条已发射的指令读。通常，我们希望读同一个寄存器的指令在发射时不产生冲突，因此天然地我们需要使用多 bit 的 counter 来对读者进行计数。但相比写者，我们不需要考虑读者的先后顺序问题，因此将 WAR 冒险移到写回时再判断是合理的。
    * 一种自然的实现 chaining 想法是，因为几乎所有的 RVV 指令都是顺序读写向量寄存器，那么可以用寄存器地址来记录每个指令的进度。当 A 指令与先发射的 B 指令有冒险时，只要保证 A 指令对冒险寄存器的读写进度不超过 B 指令即可。
      * 如果仅实现 RAW chaining，那只需要记录指令的写回进度就可以了：每个指令有一个额外的地址记录写回的顺序，每个寄存器有一个 id 记录写该寄存器的指令，以及一个 counter 记录有多少读者正在读该寄存器。当发射 WAW 或者 WAR 冒险时，暂停发射。当发生 RAW 冒险时，可以发射该指令，但标记它依赖于寄存器 id 记录的指令，它的读进度不能超过 id 对应指令的写进度。
      * 要实现 WAR chaining 则需要额外记录读的进度，但这还不够，因为一个写者可能依赖于前面的多个读者，同时跟踪多个读者的进度的实现比较复杂。另外一种选择是让读者也有序，后面的读者的读进度不能超过 RAR 冒险中的前一个读者（这通常不是我们想看到的），这样的话写者只需要跟踪依赖的最后一个读者即可。WAW chaining 的讨论是类似的，不过 WAW 天然地使得写者有序了。
      * 但 VL 的存在使得实现 WAR, WAW chaining 有额外的影响。设想 A 指令在 B 指令后，它们有着 WAW 冒险，如果 A 的 VL 小于 B，且在 A 后的指令跟踪依赖时只跟踪了 A，由于 A 的 VL 更小，它可以先于 B 指令完成，这导致跟踪 A 的指令认为自己已经没有依赖了，导致其读的进度超过 B 的写回进度。
      * 这也有两种解决办法。一种是限制 rvvcore 顺序提交，这样在 B 后的 A 指令不可能先于 B 完成。或者，由于上述冒险发生的前提条件是 VL 变小，而 VL 由 vsetvl 系列指令控制，我们可以让寄存器除了记录指令 id 外，还记录指令的 VL，当待发射的指令 VL 小于它依赖于的指令时暂停发射有 WAW，WAR 冒险的指令。或者开销更小的，只记录 1bit 的 version 标识，每次 vsetvl 更新 vl 后我们将 verison 翻转，当 version 不一致时暂停发射 WAW，WAR 冒险的指令。

    * 在前面对 chaining 的讨论中，我们默认地采取了 scalar cpu 的假设：每条指令的读写是针对单个寄存器。RVV 中 LMUL 的存在，导致一条指令可以读写多个连续的寄存器，这进一步会复杂化我们的设计。
      * 同样的，我们可以选择同时跟踪多条依赖的指令来解决冒险，但这个实现过于复杂。注意到，RVV SPEC 要求只能读写对齐的连续寄存器。例如 LMUL = 4 时，读写的连续寄存器的起始寄存器编号必须是 4 的倍数。因此在 LMUL 不改变时，将连续的寄存器视为寄存器组整体考虑冒险是合理的。
      * 在改变 LMUL 时排空流水线，这样保证同一时间所有的指令都读同一个寄存器组，因此多读多写也只需要考虑一个寄存器。但是这还不够，因为存在 narrowing, widening 指令。narrowing 更容易解决，它会读写一个更小的寄存器组，但我们只需要设置为它读写 LMUL 指定宽度的寄存器组，并添加一个类似于 vstart 的读写初始偏移即可。widening 很麻烦，因为它会读写一个更大的寄存器组（由于目前 RVV 指令中宽度最多翻一倍，因此相当于读或写两个连续的寄存器），可能产生多个冒险。
      * 另外一种做法是将指令分解为 micro op，由 LMUL <= 8，因此一条指令最多产生 8 个 micro op，每个 micro op 只能读，写一个寄存器，并有着独立的冒险检测。但这样做降低了 issue 的效率，并且不是所有的指令都能够通过 micro op 进行解决，例如 reduction 类指令以及 shuffle 类指令（slide, vrgather, vcompress 这几个指令都不太方便拆解）
      * 一种我认为比较合适的做法是综合排空流水线和 micro op，如果我们假定切换 LMUL 的情况比较稀少，那么排空流水线的开销是能够接受的。为了处理 widening 指令，我们则采用 micro op，由于宽度最多翻倍，因此我们最多生成两条 micro op。另外，widening 相关的指令都是能够通过 micro op 拆解的（注意 widening reduction 指令中，需要访问的寄存器组是正常宽度的，只是在计算前需要拓宽）。

  * 引入重命名机制后，对上面的讨论有哪些影响？**TODO**

## Design

* 目前的握手信号处理感觉有些混乱，valid, ready 信号之间的依赖关系从命名上看得不够清楚
  * decoder <-> scalar core, decoder 会在下一级流水线能（即 launcher 拉高了自己的 ready 或者 下一级寄存器不存在效信号）时将 ready 信号拉高，因此 decoder 的 ready 信与 scalar core 无关
  * launcher <-> decoder, decoder 的 req_valid 信号从水线寄存器中发出，因此显然是与 launcher 的 ready 信号无关而 launcher 的 ready 信号的生成逻辑与 decoder 一致，仅赖于下一级（vrf_accesser 和 vfu）的 ready 信号
  * vrf_accesser <-> launcher, vrf_accesser 中每个 opqueue 的 ready 信号独立拉高，当 op_req_i 中请求的 opqueue 都 ready 时，vrf_accesser 的 ready 信号会拉高，因此总的说来，vrf_accesser 的 ready 信号不依赖于 launcher 的 valid 信号。但由于 lanes.sv 中整合了每个 lane 的信号，导致每个 vrf_accesser 收到的 valid 的信号是依赖于自身发出的 ready 信号的（当所有 lane 的 vrf_accesser 的 ready 拉高时，vrf_accesser 才可能收到拉高的 valid 信号）
  * vfu <-> launcher, vfu 当自己的 state 为 IDLE 时，拉高 ready 信号，因此 ready 信号与 launcher 的 valid 信号无关，由于与 vrf_accesser 同样的原因，vfu 收到的 valid 信号依赖于自己发出的 ready 信号

* 三种可能的 register layout

* In addition, except for mask load instructions, any element in the tail of a mask result can also be written with the value the mask-producing operation would have calculated with vl=VLMAX. Furthermore, for mask-logical instructions and vmsbf.m, vmsif.m, vmsof.m mask-manipulation instructions, any element in the tail of the result can be written with the value the mask-producing operation would have calculated with vl=VLEN, SEW=8, and LMUL=8 (i.e., all bits of the mask register can be overwritten). **TODO: 这段话对实现 mask 有哪些影响？**

* 资源使用影响：
  * mem_shuffler_v0: lane2 lut 165, lane 4 lut 381
  * mem_shuffler_v1: lane2 lut 135, lane 4 lut 315
  * mem_shuffler_v2: **TODO** (reuse logic if smaller bandwidth is acceptable)

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
  * 由于写入 mask 的指令都是 vta 的，因此不用担心 mask 的 bit 粒度破坏了原有的 byte 数据
  * 优点：涉及 mask 的指令都不需要 shuffle 了，包括指令用到的 mask bits，以及算数指令产生的 mask bits
  * 缺点：shuffle 代价变大，shuffle 的粒度从 byte 变成 bit（**是否如此？因为 EW1 只是内部的一种表示，对于正常运算的 operand，我们可以假定它的宽度不为 EW1？即 quick shuffle 不支持 EW1**），虽然这可以一定程度的缓解，例如令 quick shuffle 中不支持 EW1，需要处理时发射 micro op 走一遍 slow shuffle 路径。但 mem shuffle 不是很好处理，因为 ISA 层提供了 vlm, vsm 指令。
  * 另外 mem shuffle 除了操作数，还涉及到 mask，这应该不会带来额外的开销，仅仅是从 EW8 排布的 shuffle 换成 EW1 而已。
  * 考虑 section 15 中 mask 相关指令，EW1 的排布对这些指令的实现有影响吗？
    * 首先 and，or 等等逻辑运算指令是没有影响的
    * 其次是 vcpop，vfirst, vmsbf 等等指令，这些指令不能在 lane 内部完成，需要将所有 lane 数据 shuffle 为 mem layout 之后才能进行计算。在已知 EW 的情况下，EW8/EW1 都不需要额外逻辑就能转化为 mem layout

    因此目前认为 EW1 不会影响 mask 指令的实现

* 尽可能地让各个 lane 同步可以简化设计，目前的想法是：将 vstart 和 vl 与 lane 的数目对齐，然后利用 mask 将多余的计算舍弃掉（是否简化了呢？如果允许各个 lane 的工作量不一致，在 valu wrapper 中计算 skipped bytes 时是否会相对容易一些？）。
* 实现一些 log helper

## Non-speculative branch

* Only non-speculative instruction can be sent to this core.
* `flush_i` signal is only used to flush interrupted memory instruction.
* Decoder will assert `done` in the same cycle of receiving rvv inst, except VWXUNARY0, VWFUNARY0 and floating instructions. These instructions will return 64bits data or fflags to scalar cpu.
