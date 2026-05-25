# CPU_YELLOW 五级流水线 MIPS 处理器设计规格说明书 (Spec)

**课程名称：** 计算机组成与系统结构
**课程编号：** U10M11007.02

---

## 1. 概述

### 1.1 设计目标
设计一款兼容 MIPS32 指令系统的五级流水线处理器，支持 57 条指令，具备完整的数据前递、冒险检测、分支预测、CP0 例外处理等功能。处理器采用经典的五级流水线结构：取指(IF)、译码(ID)、执行(EX)、访存(MEM)、写回(WB)。

### 1.2 顶层接口

| 端口名 | 方向 | 位宽 | 描述 |
| --- | --- | --- | --- |
| clk | input | 1 | 全局时钟，所有时序逻辑在上升沿更新 |
| rst_n | input | 1 | 异步复位，低电平有效 |
| instr | input | 32 | 指令输入，来自外部指令存储器 |
| instr_addr | output | 32 | 指令地址（当前 PC），送指令存储器地址端口 |
| dmem_addr | output | 32 | 数据存储器地址 |
| dmem_wdata | output | 32 | 数据存储器写数据 |
| dmem_rdata | input | 32 | 数据存储器读数据 |
| dmem_we | output | 1 | 数据存储器写使能，高有效 |
| dmem_re | output | 1 | 数据存储器读使能，高有效 |

---

## 2. 流水线结构

### 2.1 五级流水线概述

```
    +------+      +------+      +------+      +------+      +------+
    |  IF  | ---> |  ID  | ---> |  EX  | ---> | MEM  | ---> |  WB  |
    +------+      +------+      +------+      +------+      +------+
       |              |              |              |              |
    PC更新        寄存器读取      ALU运算      数据存储器     寄存器写回
    指令取指      控制信号译码   地址计算      访存操作       结果写回
                  分支判断       分支解析
                  数据前递检测
```

- **IF (Instruction Fetch)**: 发送 PC 到指令存储器，锁存返回的指令到 IF/ID 段间寄存器
- **ID (Instruction Decode)**: 译码指令、读取寄存器堆、生成控制信号、检测数据冒险、计算分支目标地址
- **EX (Execute)**: ALU 运算、乘法/除法运算、数据前递选择、分支解析
- **MEM (Memory Access)**: 数据存储器读写、CP0 访问、例外检测
- **WB (Write Back)**: 将结果写回寄存器堆

### 2.2 段间寄存器

每个流水段之间通过段间寄存器传递数据：

**IF/ID 寄存器:**
- `pc_plus4`: PC+4 值
- `instr`: 32位指令

**ID/EX 寄存器:**
- `pc_plus4`, `instr`, `reg_data1`, `reg_data2`, `sign_ext_imm`
- 控制信号: `reg_dst`, `alu_src`, `mem_read`, `mem_write`, `reg_write`, `mem_to_reg`, `alu_op`, `branch`, `jump`, `jal`, `jr`, `is_load`, `is_store`, `hi_write`, `lo_write`, `cp0_write`, `cp0_read`, `eret`, `syscall`, `break`

**EX/MEM 寄存器:**
- `alu_result`, `reg_data2`, `write_reg`
- 控制信号: `mem_read`, `mem_write`, `reg_write`, `mem_to_reg`, `jal`, `hi_write`, `lo_write`, `cp0_write`, `cp0_read`, `eret`
- `pc_plus4` (用于 JAL)
- `hi_result`, `lo_result`

**MEM/WB 寄存器:**
- `mem_data`, `alu_result`, `write_reg`
- 控制信号: `reg_write`, `mem_to_reg`, `jal`
- `pc_plus4`
- `hi_result`, `lo_result`

---

## 3. 指令集

本处理器支持全部 57 条 MIPS 指令，分为以下类别：

### 3.1 指令格式

所有指令长度均为 32 位，分为三种格式：

- **R-Type**: `opcode[31:26] rs[25:21] rt[20:16] rd[15:11] shamt[10:6] funct[5:0]`
- **I-Type**: `opcode[31:26] rs[25:21] rt[20:16] immediate[15:0]`
- **J-Type**: `opcode[31:26] instr_index[25:0]`

### 3.2 算术运算指令 (14条)

| 指令 | 格式 | Opcode | Funct | 功能 |
| --- | --- | --- | --- | --- |
| ADD | R | 6'h00 | 6'h20 | 有符号加法(溢出检测) |
| ADDI | I | 6'h08 | - | 加立即数(有符号扩展,溢出检测) |
| ADDU | R | 6'h00 | 6'h21 | 无符号加法 |
| ADDIU | I | 6'h09 | - | 加立即数(无溢出检测) |
| SUB | R | 6'h00 | 6'h22 | 有符号减法(溢出检测) |
| SUBU | R | 6'h00 | 6'h23 | 无符号减法 |
| SLT | R | 6'h00 | 6'h2A | 有符号小于置1 |
| SLTI | I | 6'h0A | - | 有符号小于立即数置1 |
| SLTU | R | 6'h00 | 6'h2B | 无符号小于置1 |
| SLTIU | I | 6'h0B | - | 无符号小于立即数置1 |
| DIV | R | 6'h00 | 6'h1A | 有符号除法(HI/LO) |
| DIVU | R | 6'h00 | 6'h1B | 无符号除法(HI/LO) |
| MULT | R | 6'h00 | 6'h18 | 有符号乘法(HI/LO) |
| MULTU | R | 6'h00 | 6'h19 | 无符号乘法(HI/LO) |

### 3.3 逻辑运算指令 (8条)

| 指令 | 格式 | Opcode | Funct | 功能 |
| --- | --- | --- | --- | --- |
| AND | R | 6'h00 | 6'h24 | 位与 |
| ANDI | I | 6'h0C | - | 立即数位与(0扩展) |
| LUI | I | 6'h0F | - | 加载立即数到高16位 |
| NOR | R | 6'h00 | 6'h27 | 位或非 |
| OR | R | 6'h00 | 6'h25 | 位或 |
| ORI | I | 6'h0D | - | 立即数位或(0扩展) |
| XOR | R | 6'h00 | 6'h26 | 位异或 |
| XORI | I | 6'h0E | - | 立即数位异或(0扩展) |

### 3.4 移位指令 (6条)

| 指令 | 格式 | Opcode | Funct | 功能 |
| --- | --- | --- | --- | --- |
| SLLV | R | 6'h00 | 6'h04 | 变量逻辑左移 |
| SLL | R | 6'h00 | 6'h00 | 立即数逻辑左移 |
| SRAV | R | 6'h00 | 6'h07 | 变量算术右移 |
| SRA | R | 6'h00 | 6'h03 | 立即数算术右移 |
| SRLV | R | 6'h00 | 6'h06 | 变量逻辑右移 |
| SRL | R | 6'h00 | 6'h02 | 立即数逻辑右移 |

### 3.5 分支跳转指令 (12条)

| 指令 | 格式 | Opcode | Funct/RT | 功能 |
| --- | --- | --- | --- | --- |
| BEQ | I | 6'h04 | - | 相等转移 |
| BNE | I | 6'h05 | - | 不等转移 |
| BGEZ | I | 6'h01 | 5'h01 | 大于等于0转移 |
| BGTZ | I | 6'h07 | 5'h00 | 大于0转移 |
| BLEZ | I | 6'h06 | 5'h00 | 小于等于0转移 |
| BLTZ | I | 6'h01 | 5'h00 | 小于0转移 |
| BGEZAL | I | 6'h01 | 5'h11 | 大于等于0调用并保存返回地址 |
| BLTZAL | I | 6'h01 | 5'h10 | 小于0调用并保存返回地址 |
| J | J | 6'h02 | - | 无条件直接跳转 |
| JAL | J | 6'h03 | - | 无条件跳转并保存返回地址 |
| JR | R | 6'h00 | 6'h08 | 寄存器跳转 |
| JALR | R | 6'h00 | 6'h09 | 寄存器跳转并保存返回地址 |

### 3.6 数据移动指令 (4条)

| 指令 | 格式 | Opcode | Funct | 功能 |
| --- | --- | --- | --- | --- |
| MFHI | R | 6'h00 | 6'h10 | HI -> GPR |
| MFLO | R | 6'h00 | 6'h12 | LO -> GPR |
| MTHI | R | 6'h00 | 6'h11 | GPR -> HI |
| MTLO | R | 6'h00 | 6'h13 | GPR -> LO |

### 3.7 自陷指令 (2条)

| 指令 | 格式 | Opcode | Funct | 功能 |
| --- | --- | --- | --- | --- |
| BREAK | R | 6'h00 | 6'h0D | 触发断点例外 |
| SYSCALL | R | 6'h00 | 6'h0C | 触发系统调用例外 |

### 3.8 访存指令 (8条)

| 指令 | 格式 | Opcode | 功能 |
| --- | --- | --- | --- |
| LB | I | 6'h20 | 取字节(有符号扩展) |
| LBU | I | 6'h24 | 取字节(无符号扩展) |
| LH | I | 6'h21 | 取半字(有符号扩展) |
| LHU | I | 6'h25 | 取半字(无符号扩展) |
| LW | I | 6'h23 | 取字 |
| SB | I | 6'h28 | 存字节 |
| SH | I | 6'h29 | 存半字 |
| SW | I | 6'h2B | 存字 |

### 3.9 特权指令 (3条)

| 指令 | 格式 | Opcode | Funct | 功能 |
| --- | --- | --- | --- | --- |
| ERET | R | 6'h10 | 6'h18 | 例外处理返回 |
| MFC0 | R | 6'h10 | rs=5'h00 | 读 CP0 寄存器 |
| MTC0 | R | 6'h10 | rs=5'h04 | 写 CP0 寄存器 |

---

## 4. 模块设计

### 4.1 顶层模块 (cpu_yellow_top)

**功能:** 实例化所有子模块，连接五级流水线的段间寄存器。

**子模块实例化列表:**
- `if_stage`: 取指阶段
- `id_stage`: 译码阶段
- `ex_stage`: 执行阶段
- `mem_stage`: 访存阶段
- `wb_stage`: 写回阶段
- `regfile`: 寄存器堆
- `hazard_detection`: 冒险检测单元
- `forwarding_unit`: 数据前递单元
- `cp0`: 协处理器0

### 4.2 IF 阶段 (if_stage)

**功能:** 管理 PC 更新，生成指令地址。

**内部逻辑:**
- 上电复位时 PC = 0xBFC0_0000
- 正常情况: PC_next = PC + 4
- 分支跳转: PC_next = branch_target (来自 ID 阶段)
- 分支预测策略: Always Taken — 只要 ID 阶段解码出分支指令且条件满足（或不条件跳转如 J/JAL），立即在下一拍更新 PC 为跳转目标
- 延迟槽支持: 分支指令后的指令（延迟槽）必须执行
- Stall 时 PC 保持不变

**接口:**
| 端口 | 方向 | 位宽 | 描述 |
| --- | --- | --- | --- |
| clk | input | 1 | 时钟 |
| rst_n | input | 1 | 复位 |
| stall | input | 1 | 流水线暂停 |
| branch_target | input | 32 | 分支目标地址 |
| is_taken | input | 1 | 是否跳转(来自ID) |
| pc | output | 32 | 当前PC |
| pc_plus4 | output | 32 | PC+4 |
| instr_addr | output | 32 | 指令存储器地址 |

### 4.3 ID 阶段 (id_stage)

**功能:** 指令译码、寄存器读取、控制信号生成、分支目标计算。

**内部逻辑:**
- 根据 opcode 和 funct 字段译码出所有控制信号
- 读取 rs 和 rt 寄存器
- 对立即数进行符号扩展或零扩展（根据指令类型 ANDI/ORI/XORI 使用零扩展，其余 I-type 使用符号扩展）
- 计算分支目标地址: branch_target = PC+4 + SignExtend(offset)<<2
- J/JAL 目标地址: {PC[31:28], instr_index, 2'b00}
- 检测数据冒险，生成 stall 信号(与 hazard_detection 协同)
- 生成前递控制信号

**控制信号真值表:**

| 指令类型 | RegDst | ALUSrc | MemtoReg | RegWrite | MemRead | MemWrite | Branch | Jump | JAL | JR |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| R-Type | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| ADDI/ADDIU/SLTI/SLTIU | 0 | 1 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| ANDI/ORI/XORI | 0 | 1 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| LUI | 0 | 1 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| LW/LB/LBU/LH/LHU | 0 | 1 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 0 |
| SW/SB/SH | x | 1 | x | 0 | 0 | 1 | 0 | 0 | 0 | 0 |
| BEQ/BNE/BGEZ/BGTZ/BLEZ/BLTZ | x | 0 | x | 0 | 0 | 0 | 1 | 0 | 0 | 0 |
| BGEZAL/BLTZAL | x | 0 | x | 1 | 0 | 0 | 1 | 0 | 1 | 0 |
| J | x | x | x | 0 | 0 | 0 | x | 1 | 0 | 0 |
| JAL | x | x | 1 | 1 | 0 | 0 | x | 1 | 1 | 0 |
| JR | x | x | x | 0 | 0 | 0 | x | x | 0 | 1 |
| JALR | 1 | x | 1 | 1 | 0 | 0 | x | x | 1 | 1 |

**接口:**
| 端口 | 方向 | 位宽 | 描述 |
| --- | --- | --- | --- |
| clk | input | 1 | 时钟 |
| rst_n | input | 1 | 复位 |
| instr | input | 32 | 指令 |
| pc_plus4_i | input | 32 | PC+4 (来自IF) |
| reg_write_data | input | 32 | 写回数据 |
| reg_write_addr | input | 5 | 写回寄存器地址 |
| reg_write_en | input | 1 | 写回使能 |
| forward_ex | input | 32 | EX前递数据 |
| forward_mem | input | 32 | MEM前递数据 |
| forward_ex_en | input | 2 | EX前递使能 |
| forward_mem_en | input | 2 | MEM前递使能 |
| stall | input | 1 | 暂停信号 |
| branch_target | output | 32 | 分支目标 |
| is_taken | output | 1 | 是否跳转 |
| reg_data1_o | output | 32 | 寄存器数据1 |
| reg_data2_o | output | 32 | 寄存器数据2 |
| sign_ext_imm | output | 32 | 符号扩展立即数 |
| pc_plus4_o | output | 32 | PC+4 |
| alu_op | output | 4 | ALU操作码 |
| reg_dst | output | 1 | 目标寄存器选择 |
| alu_src | output | 1 | ALU源选择 |
| mem_read | output | 1 | 存储器读 |
| mem_write | output | 1 | 存储器写 |
| reg_write | output | 1 | 寄存器写 |
| mem_to_reg | output | 2 | 写回数据选择 |
| is_load | output | 1 | 是否load指令 |
| is_store | output | 1 | 是否store指令 |
| load_type | output | 3 | load类型编码 |
| store_type | output | 3 | store类型编码 |

### 4.4 EX 阶段 (ex_stage)

**功能:** ALU 运算、乘法/除法、数据前递多路选择。

**ALU 操作编码:**
| ALUOp | 操作 | 描述 |
| --- | --- | --- |
| 4'h0 | ADD | 加法 |
| 4'h1 | SUB | 减法 |
| 4'h2 | AND | 位与 |
| 4'h3 | OR | 位或 |
| 4'h4 | XOR | 位异或 |
| 4'h5 | NOR | 位或非 |
| 4'h6 | SLT | 有符号小于 |
| 4'h7 | SLTU | 无符号小于 |
| 4'h8 | SLL | 逻辑左移 |
| 4'h9 | SRL | 逻辑右移 |
| 4'hA | SRA | 算术右移 |
| 4'hB | LUI | 左移16位 |
| 4'hC | PASS_B | 直通B |

**数据前递多路选择:**
- 操作数 A (rs): 来自 reg_data1 或 forward_ex_a 或 forward_mem_a
- 操作数 B (rt): 来自 reg_data2 或 forward_ex_b 或 forward_mem_b

**乘法/除法:**
- MULT/MULTU: 在 EX 阶段启动，多周期完成（简化设计中假设单周期）
- DIV/DIVU: 在 EX 阶段计算
- 结果存入 HI/LO 寄存器

**接口:**
| 端口 | 方向 | 位宽 | 描述 |
| --- | --- | --- | --- |
| clk | input | 1 | 时钟 |
| rst_n | input | 1 | 复位 |
| reg_data1 | input | 32 | 寄存器数据1(已前递) |
| reg_data2 | input | 32 | 寄存器数据2(已前递) |
| sign_ext_imm | input | 32 | 立即数 |
| pc_plus4_i | input | 32 | PC+4 |
| alu_op | input | 4 | ALU操作 |
| alu_src | input | 1 | ALU源选择 |
| reg_dst | input | 1 | 目标寄存器选择 |
| hi_write | input | 1 | HI写使能 |
| lo_write | input | 1 | LO写使能 |
| hi_read | input | 1 | HI读使能 |
| lo_read | input | 1 | LO读使能 |
| alu_result | output | 32 | ALU结果 |
| hi_result | output | 32 | HI值 |
| lo_result | output | 32 | LO值 |
| write_reg | output | 5 | 写寄存器地址 |
| overflow | output | 1 | 溢出标志 |
| pc_plus4_o | output | 32 | PC+4 |

### 4.5 MEM 阶段 (mem_stage)

**功能:** 数据存储器访问，字节/半字/字读写处理。

**Load 数据对齐与扩展:**
- LW: 直接使用 32 位数据
- LH: 取半字，有符号扩展到 32 位
- LHU: 取半字，无符号扩展到 32 位
- LB: 取字节，有符号扩展到 32 位
- LBU: 取字节，无符号扩展到 32 位

**Store 数据处理:**
- SW: 写入完整 32 位
- SH: 写入低 16 位
- SB: 写入低 8 位

**异常检测:**
- LH/LHU/SH: 地址 bit0 必须为 0，否则触发 AddressError
- LW/SW: 地址 bit[1:0] 必须为 0，否则触发 AddressError

**接口:**
| 端口 | 方向 | 位宽 | 描述 |
| --- | --- | --- | --- |
| clk | input | 1 | 时钟 |
| rst_n | input | 1 | 复位 |
| alu_result | input | 32 | ALU结果(访存地址) |
| reg_data2 | input | 32 | 写数据 |
| write_reg_i | input | 5 | 目标寄存器 |
| mem_read | input | 1 | 存储器读使能 |
| mem_write | input | 1 | 存储器写使能 |
| load_type | input | 3 | load类型 |
| store_type | input | 3 | store类型 |
| pc_plus4_i | input | 32 | PC+4 |
| dmem_rdata | input | 32 | 数据存储器读数据 |
| dmem_addr | output | 32 | 数据存储器地址 |
| dmem_wdata | output | 32 | 数据存储器写数据 |
| dmem_we | output | 1 | 写使能 |
| dmem_re | output | 1 | 读使能 |
| mem_data | output | 32 | 处理后的读数据 |
| alu_result_o | output | 32 | ALU结果(直通) |
| write_reg_o | output | 5 | 目标寄存器 |
| pc_plus4_o | output | 32 | PC+4 |
| addr_error | output | 1 | 地址错误 |

### 4.6 WB 阶段 (wb_stage)

**功能:** 选择写回数据源，写回寄存器堆。

**写回数据源选择 (MemtoReg):**
| MemtoReg | 数据源 |
| --- | --- |
| 2'b00 | ALU 结果 |
| 2'b01 | 存储器读数据 |
| 2'b10 | PC+4 (JAL/JALR) |
| 2'b11 | CP0 读数据 |

**接口:**
| 端口 | 方向 | 位宽 | 描述 |
| --- | --- | --- | --- |
| mem_data | input | 32 | 存储器读数据 |
| alu_result | input | 32 | ALU结果 |
| pc_plus4 | input | 32 | PC+4 |
| cp0_data | input | 32 | CP0数据 |
| write_reg_i | input | 5 | 目标寄存器 |
| reg_write_i | input | 1 | 写使能 |
| mem_to_reg | input | 2 | 数据选择 |
| reg_write_data | output | 32 | 写回数据 |
| reg_write_addr | output | 5 | 写回地址 |
| reg_write_en | output | 1 | 写回使能 |

### 4.7 寄存器堆 (regfile)

**功能:** 32×32 通用寄存器堆，r0 硬连线为 0。

**特性:**
- 异步读，同步写（时钟上升沿写入）
- r0 寄存器读始终返回 0，写入被忽略
- 支持双端口读（rs, rt）单端口写

**接口:**
| 端口 | 方向 | 位宽 | 描述 |
| --- | --- | --- | --- |
| clk | input | 1 | 时钟 |
| rst_n | input | 1 | 复位(清零) |
| read_addr1 | input | 5 | 读地址1 (rs) |
| read_addr2 | input | 5 | 读地址2 (rt) |
| read_data1 | output | 32 | 读数据1 |
| read_data2 | output | 32 | 读数据2 |
| write_en | input | 1 | 写使能 |
| write_addr | input | 5 | 写地址 |
| write_data | input | 32 | 写数据 |

### 4.8 ALU (alu)

**功能:** 执行算术/逻辑/移位运算。

**操作:**
| ALUOp | 操作 | 表达式 |
| --- | --- | --- |
| 4'h0 | ADD | A + B |
| 4'h1 | SUB | A - B |
| 4'h2 | AND | A & B |
| 4'h3 | OR | A \| B |
| 4'h4 | XOR | A ^ B |
| 4'h5 | NOR | ~(A \| B) |
| 4'h6 | SLT | $signed(A) < $signed(B) |
| 4'h7 | SLTU | A < B |
| 4'h8 | SLL | B << shamt |
| 4'h9 | SRL | B >> shamt |
| 4'hA | SRA | $signed(B) >>> shamt |
| 4'hB | LUI | {B[15:0], 16'b0} |
| 4'hC | PASS_B | B |

**溢出检测(ADD/SUB/ADDI):**
- 两个同号数相加结果异号 -> 溢出
- 两个异号数相减结果与被减数异号 -> 溢出

### 4.9 冒险检测单元 (hazard_detection)

**功能:** 检测 Load-Use 数据冒险，生成 stall 信号。

**检测逻辑:**
```verilog
// Load-Use hazard: lw后一条指令使用lw的目标寄存器
if (EX/MEM.mem_read && 
    (EX/MEM.write_reg == ID/EX.rs || EX/MEM.write_reg == ID/EX.rt)) begin
    stall = 1; // 插入1个气泡，暂停IF和ID
end
```

**Stall 效果:**
- PC 保持不变
- IF/ID 寄存器保持不变
- ID/EX 寄存器载入 NOP (控制信号清零)

### 4.10 数据前递单元 (forwarding_unit)

**功能:** 检测 RAW (Read-After-Write) 数据冒险，生成前递控制信号。

**前递检测逻辑:**
```verilog
// Forward from EX/MEM (优先级高)
if (EX/MEM.reg_write && EX/MEM.write_reg != 0 &&
    EX/MEM.write_reg == ID/EX.rs)
    forward_a_sel = 2'b10; // 从EX/MEM前递

// Forward from MEM/WB (优先级低)
else if (MEM/WB.reg_write && MEM/WB.write_reg != 0 &&
         MEM/WB.write_reg == ID/EX.rs)
    forward_a_sel = 2'b01; // 从MEM/WB前递

// 类似逻辑处理rt (forward_b_sel)
```

**前递源选择:**
| ForwardSel | 数据源 |
| --- | --- |
| 2'b00 | 寄存器数据 (无前递) |
| 2'b01 | MEM/WB 阶段结果 |
| 2'b10 | EX/MEM 阶段结果 |

### 4.11 CP0 (cp0)

**功能:** 系统控制协处理器，管理例外和中断。

**实现的 CP0 寄存器:**

| 寄存器号 | 选择子 | 名称 | 描述 |
| --- | --- | --- | --- |
| 12 | 0 | SR (Status) | 状态寄存器 |
| 13 | 0 | Cause | 例外原因寄存器 |
| 14 | 0 | EPC | 例外程序计数器 |

**Status 寄存器字段:**
| 位 | 字段 | 描述 |
| --- | --- | --- |
| 0 | IE | 全局中断使能 |
| 1 | EXL | 例外级别 (1=在例外处理中) |
| 2 | 保留 | - |

**Cause 寄存器字段:**
| 位 | 字段 | 描述 |
| --- | --- | --- |
| [6:2] | ExcCode | 例外代码 |
| [8] | IP | 中断pending位 |

**例外代码 (ExcCode):**
| 代码 | 例外 |
| --- | --- |
| 5'h00 | Int (中断) |
| 5'h04 | AdEL (地址错误-取指/取数) |
| 5'h05 | AdES (地址错误-存数) |
| 5'h08 | Sys (系统调用) |
| 5'h09 | Bp (断点) |
| 5'h0A | RI (保留指令) |
| 5'h0C | Ov (溢出) |

**CP0 接口:**
| 端口 | 方向 | 位宽 | 描述 |
| --- | --- | --- | --- |
| clk | input | 1 | 时钟 |
| rst_n | input | 1 | 复位 |
| cp0_read | input | 1 | 读使能 |
| cp0_write | input | 1 | 写使能 |
| cp0_addr | input | 5 | CP0寄存器号 |
| cp0_sel | input | 3 | 选择子 |
| cp0_data_in | input | 32 | 写数据 |
| cp0_data_out | output | 32 | 读数据 |
| exception_type | input | 5 | 例外类型 |
| exception_pc | input | 32 | 例外PC |
| is_in_delay_slot | input | 1 | 是否延迟槽 |
| exception_occurred | output | 1 | 例外发生 |
| exception_target | output | 32 | 例外入口地址(0xBFC0_0380) |
| eret | input | 1 | ERET指令 |
| epc | output | 32 | EPC值 |

---

## 5. 冒险处理详细设计

### 5.1 数据冒险

**分类与处理策略:**

1. **EX 级前递 (1-cycle hazard):**
   - 场景: `ADD $1, $2, $3` 后紧跟 `SUB $4, $1, $5`
   - 检测: EX/MEM 的 write_reg 匹配 ID/EX 的 rs 或 rt
   - 处理: 将 EX/MEM 的 ALU 结果直接前递到 EX 阶段输入

2. **MEM 级前递 (2-cycle hazard):**
   - 场景: `ADD $1, $2, $3` -> `NOP` -> `SUB $4, $1, $5`
   - 检测: MEM/WB 的 write_reg 匹配 ID/EX 的 rs 或 rt
   - 处理: 将 MEM/WB 的结果前递到 EX 阶段输入

3. **Load-Use 冒险 (需要 Stall):**
   - 场景: `LW $1, 0($2)` 后紧跟 `ADD $3, $1, $4`
   - 检测: ID/EX 阶段为 load 指令，且目标寄存器匹配下一条指令的源寄存器
   - 处理: 插入 1 个 stall 周期（因为 DMEM 的读取延迟 1 拍）

4. **双前递冲突:**
   - 当 EX/MEM 和 MEM/WB 同时匹配同一个源寄存器时，优先使用 EX/MEM 的数据（更新的数据）

### 5.2 控制冒险

**分支预测策略: Always Taken**

- 在 ID 阶段检测分支指令并计算目标地址
- 默认预测所有分支都跳转
- ID 阶段给出 is_taken 信号和 branch_target，IF 阶段在下一拍更新 PC

**延迟槽支持:**

MIPS 规范要求分支指令后紧跟一条延迟槽指令。该指令无论分支是否跳转都会被执行。

```
BEQ $1, $2, target
NOP                    ; 延迟槽指令
```

**预测错误处理:**
- 当 ID 阶段判断实际不跳转 (Not Taken):
  - IF 阶段的 PC 已经被更新为跳转目标 -> 需要纠正
  - 将 IF/ID 寄存器清零（插入 NOP）
  - 下一拍 PC 更新为正确的 PC+4

### 5.3 结构冒险

由于采用独立的指令存储器和数据存储器（哈佛架构），不存在结构冒险。

---

## 6. 时序要求

### 6.1 存储器时序

**指令存储器 (IMEM):**
- instr_addr 在时钟周期 T 给出
- instr 在时钟周期 T+1 返回（1 拍延迟）
- 设计影响: IF/ID 寄存器在 T+1 拍锁存 instr

**数据存储器 (DMEM):**
- 读: dmem_re 有效时，dmem_addr 在周期 T 给出，dmem_rdata 在周期 T+1 返回
- 写: clk 上升沿，若 dmem_we 有效，将 dmem_wdata 写入 dmem_addr

### 6.2 寄存器堆时序

- 读: 组合逻辑，异步读出
- 写: clk 上升沿写入

### 6.3 PC 更新时序

- PC 在 clk 上升沿更新
- 复位时 PC = 0xBFC0_0000

---

## 7. 存储器映射

### 7.1 地址空间

| 虚拟地址范围 | 段名称 | 大小 | 用途 |
| --- | --- | --- | --- |
| 0xBFC0_0000 - 0xBFC0_FFFF | Code Segment | 64 KB | 指令存储器 |
| 0xBFC1_0000 - 0xBFC1_FFFF | Data Segment | 64 KB | 数据存储器 |
| 0xBFC0_0380 | Exception Vector | - | 例外入口地址 |
| 0xBFC0_0000 | Reset Vector | - | 复位入口地址 |

### 7.2 物理地址映射

Physical Address = Virtual Address - 0xA000_0000

- IMEM: 当 PC[31:16] == 16'hBFC0 时选中，局部地址 = PC[15:2]
- DMEM: 当 Addr[31:16] == 16'hBFC1 时选中，局部地址 = Addr[15:2]

---

## 8. 复位行为

- 异步复位 (rst_n = 0): PC = 0xBFC0_0000，所有寄存器清零
- 同步释放: 复位信号经过两级同步器后释放
- 寄存器堆: 所有寄存器清零（r0 硬连线为 0）
- CP0: Status = 0, Cause = 0, EPC = 0
- 复位释放后，处理器从 0xBFC0_0000 开始取指执行

---

## 9. 例外与中断

### 9.1 例外处理流程

1. 例外发生时:
   - EPC = 例外指令的 PC（若在延迟槽中则为分支指令的 PC）
   - Cause.ExcCode = 例外代码
   - Status.EXL = 1
   - PC = 0xBFC0_0380（例外入口）

2. ERET 返回:
   - PC = EPC
   - Status.EXL = 0

### 9.2 例外优先级

| 优先级 | 例外 | 阶段 |
| --- | --- | --- |
| 1 | AdEL (取指地址错误) | IF |
| 2 | Reserved Instruction | ID |
| 3 | Syscall | ID |
| 4 | Breakpoint | ID |
| 5 | Overflow | EX |
| 6 | AdEL (取数) | MEM |
| 7 | AdES (存数) | MEM |

### 9.3 精确例外

处理器支持精确例外——例外发生时:
- 例外指令之前的指令全部完成
- 例外指令及其后的指令不产生效果
- 流水线冲刷，重新从例外入口取指

---

## 10. 指令编码速查表

### 10.1 R-Type 指令 (opcode = 6'b000000)

| 指令 | funct[5:0] | rs | rt | rd | shamt | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| SLL | 000000 | 00000 | rt | rd | sa | NOP = SLL $0, $0, 0 |
| SRL | 000010 | 00000 | rt | rd | sa | |
| SRA | 000011 | 00000 | rt | rd | sa | |
| SLLV | 000100 | rs | rt | rd | 00000 | |
| SRLV | 000110 | rs | rt | rd | 00000 | |
| SRAV | 000111 | rs | rt | rd | 00000 | |
| JR | 001000 | rs | 00000 | 00000 | 00000 | |
| JALR | 001001 | rs | 00000 | rd | 00000 | rd 默认为 31 |
| SYSCALL | 001100 | - | - | - | - | |
| BREAK | 001101 | - | - | - | - | |
| MFHI | 010000 | 00000 | 00000 | rd | 00000 | |
| MTHI | 010001 | rs | - | - | - | |
| MFLO | 010010 | 00000 | 00000 | rd | 00000 | |
| MTLO | 010011 | rs | - | - | - | |
| MULT | 011000 | rs | rt | 00000 | 00000 | |
| MULTU | 011001 | rs | rt | 00000 | 00000 | |
| DIV | 011010 | rs | rt | 00000 | 00000 | |
| DIVU | 011011 | rs | rt | 00000 | 00000 | |
| ADD | 100000 | rs | rt | rd | 00000 | |
| ADDU | 100001 | rs | rt | rd | 00000 | |
| SUB | 100010 | rs | rt | rd | 00000 | |
| SUBU | 100011 | rs | rt | rd | 00000 | |
| AND | 100100 | rs | rt | rd | 00000 | |
| OR | 100101 | rs | rt | rd | 00000 | |
| XOR | 100110 | rs | rt | rd | 00000 | |
| NOR | 100111 | rs | rt | rd | 00000 | |
| SLT | 101010 | rs | rt | rd | 00000 | |
| SLTU | 101011 | rs | rt | rd | 00000 | |

### 10.2 I-Type 指令

| 指令 | opcode[31:26] | rs[25:21] | rt[20:16] | immediate[15:0] |
| --- | --- | --- | --- | --- |
| BLTZ/BGEZ | 000001 | rs | 00001/10001/00000/10000 | offset |
| BEQ | 000100 | rs | rt | offset |
| BNE | 000101 | rs | rt | offset |
| BLEZ | 000110 | rs | 00000 | offset |
| BGTZ | 000111 | rs | 00000 | offset |
| ADDI | 001000 | rs | rt | immediate |
| ADDIU | 001001 | rs | rt | immediate |
| SLTI | 001010 | rs | rt | immediate |
| SLTIU | 001011 | rs | rt | immediate |
| ANDI | 001100 | rs | rt | immediate |
| ORI | 001101 | rs | rt | immediate |
| XORI | 001110 | rs | rt | immediate |
| LUI | 001111 | 00000 | rt | immediate |
| LB | 100000 | base | rt | offset |
| LH | 100001 | base | rt | offset |
| LW | 100011 | base | rt | offset |
| LBU | 100100 | base | rt | offset |
| LHU | 100101 | base | rt | offset |
| SB | 101000 | base | rt | offset |
| SH | 101001 | base | rt | offset |
| SW | 101011 | base | rt | offset |

### 10.3 J-Type 指令

| 指令 | opcode[31:26] | instr_index[25:0] |
| --- | --- | --- |
| J | 000010 | instr_index |
| JAL | 000011 | instr_index |

### 10.4 特权指令 (opcode = 6'b010000)

| 指令 | opcode[31:26] | rs[25:21] | rt[20:16] | rd[15:11] | funct[5:0] |
| --- | --- | --- | --- | --- | --- |
| MFC0 | 010000 | 00000 | rt | rd | - |
| MTC0 | 010000 | 00100 | rt | rd | - |
| ERET | 010000 | 1 | 000...000 | 011000 | |

---

## 附录A: 数据通路图

```
                          +-------------------+
                          |    Forwarding     |
                          |      Unit         |
                          +--------+----------+
                                   |
          +----------------------------------------------------+
          |                                                    |
          v                                                    v
    +----------+     +----------+     +----------+     +----------+     +----------+
    | IF/ID    |     | ID/EX    |     | EX/MEM   |     | MEM/WB   |     |          |
PC->|          |---->|          |---->|          |---->|          |---->| Register |
    | Instr Mem|     | Reg File |     |   ALU    |     | Data Mem |     |   File   |
    +----------+     +----------+     +----------+     +----------+     +----------+
         ^                |                |                |                |
         |                v                v                |                |
         |          +-----------+    +-----------+         |                |
         |          |  Hazard   |    | Branch    |         |                |
         +----------| Detection |    |  Resolve  |---------+----------------+
                    +-----------+    +-----------+
```

---

## 附录B: NOP 编码

NOP 指令编码为 `0x0000_0000`，等价于 `SLL $0, $0, 0`。

---

## 附录C: 模块层次结构

```
cpu_yellow_top
├── if_stage              # PC管理，指令地址生成
├── id_stage              # 指令译码，寄存器读，控制信号生成
│   ├── control_unit      # 主控制信号译码
│   └── alu_control       # ALU控制信号译码
├── regfile               # 32x32寄存器堆
├── ex_stage              # ALU运算，前递选择
│   └── alu               # 算术逻辑单元
├── mem_stage             # 数据存储器接口，对齐处理
├── wb_stage              # 写回选择
├── hazard_detection      # Load-Use冒险检测
├── forwarding_unit       # 数据前递控制
└── cp0                   # 协处理器0，例外管理
    ├── status_reg        # Status寄存器
    ├── cause_reg         # Cause寄存器
    └── epc_reg           # EPC寄存器
```
