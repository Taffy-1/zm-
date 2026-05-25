# CPU_YELLOW 仿真验证报告

**课程名称：** 计算机组成与系统结构
**课程编号：** U10M11007.02

---

## 1. 验证环境

| 项目 | 配置 |
| --- | --- |
| 仿真工具 | Verilator / Icarus Verilog |
| 语言 | SystemVerilog (Testbench), Verilog (RTL) |
| 波形查看 | GTKWave |
| 覆盖率工具 | Verilator --coverage |
| 测试方法 | 逐指令定向测试 |

---

## 2. 验证策略

### 2.1 验证层次

采用**自底向上**的验证策略：

1. **模块级验证**: ALU, RegFile, Control Unit 等独立模块的功能验证
2. **流水段级验证**: 各流水段（IF/ID/EX/MEM/WB）的接口和数据通路验证
3. **系统级验证**: 全指令集在完整流水线环境下的集成验证

### 2.2 测试用例设计原则

- **指令覆盖**: 每条指令至少一个测试用例
- **边界条件**: 溢出、除零、地址对齐等边界情况
- **数据冒险**: 前递、Load-Use Stall 等场景
- **控制冒险**: 分支预测正确/错误场景
- **例外路径**: SYSCALL, BREAK, Overflow 等

---

## 3. 指令验证结果

### 3.1 算术运算指令 (14条)

| 指令 | 测试内容 | 状态 | 备注 |
| --- | --- | --- | --- |
| ADD | 15+5=20 (无溢出) | PASS | |
| ADD | 溢出检测 | PASS | 0x7FFFFFFF+1 触发 Overflow |
| ADDI | 10+(-8)=2 | PASS | 立即数符号扩展正确 |
| ADDU | 10+20=30 | PASS | |
| ADDIU | $0+10=10 | PASS | |
| SUB | 20-15=5 (无溢出) | PASS | |
| SUB | 溢出检测 | PASS | 0x80000000-1 触发 Overflow |
| SUBU | 20-10=10 | PASS | |
| SLT | 5<15 → 1 | PASS | 有符号比较 |
| SLT | 15<5 → 0 | PASS | |
| SLTI | 10<5 → 0 | PASS | |
| SLTU | 无符号比较 | PASS | |
| SLTIU | 无符号立即数比较 | PASS | |
| DIV | 10÷5=2, 余0 | PASS | HI=0, LO=2 |
| DIVU | 无符号除法 | PASS | |
| MULT | 10×5=50 | PASS | HI=0, LO=50 |
| MULTU | 15×5=75 | PASS | |

**算术指令覆盖率: 14/14 (100%)**

### 3.2 逻辑运算指令 (8条)

| 指令 | 测试内容 | 状态 | 备注 |
| --- | --- | --- | --- |
| AND | 0xFF & 0xF0F = 0xF | PASS | |
| ANDI | 0xF & 0xF0 = 0 | PASS | 零扩展 |
| LUI | 0x1234 → 0x12340000 | PASS | |
| NOR | ~(0xFF\|0xF0F) | PASS | |
| OR | 0xFF \| 0xF0F = 0xFFF | PASS | |
| ORI | 0xF \| 0xF00 = 0xF0F | PASS | 零扩展 |
| XOR | 0xFF ^ 0xF0F = 0xFF0 | PASS | |
| XORI | 0xFFF ^ 0xF = 0xFF0 | PASS | |

**逻辑指令覆盖率: 8/8 (100%)**

### 3.3 移位指令 (6条)

| 指令 | 测试内容 | 状态 | 备注 |
| --- | --- | --- | --- |
| SLL | 1<<4=16 | PASS | |
| SLLV | 16<<3=128 | PASS | 变量移位 |
| SRA | -16>>>2=-4 | PASS | 算术右移(符号扩展) |
| SRAV | -16>>>3=-2 | PASS | |
| SRL | 16>>2=4 | PASS | 逻辑右移 |
| SRLV | 128>>3=16 | PASS | |

**移位指令覆盖率: 6/6 (100%)**

### 3.4 分支跳转指令 (12条)

| 指令 | 测试内容 | 状态 | 备注 |
| --- | --- | --- | --- |
| BEQ | 相等时跳转 | PASS | |
| BEQ | 不等时不跳转 | PASS | 预测错误纠正 |
| BNE | 不等时跳转 | PASS | |
| BNE | 相等时不跳转 | PASS | |
| BGEZ | >=0时跳转 | PASS | |
| BGEZ | <0时不跳转 | PASS | |
| BGTZ | >0时跳转 | PASS | |
| BLEZ | <=0时跳转 | PASS | |
| BLTZ | <0时跳转 | PASS | |
| BGEZAL | >=0跳转+保存返回 | PASS | $31=PC+8 |
| BLTZAL | <0跳转+保存返回 | PASS | |
| J | 无条件跳转 | PASS | |
| JAL | 跳转+保存返回 | PASS | |
| JR | 寄存器跳转 | PASS | |
| JALR | 寄存器跳转+保存返回 | PASS | |

**分支跳转覆盖率: 12/12 (100%)**

### 3.5 数据移动指令 (4条)

| 指令 | 测试内容 | 状态 | 备注 |
| --- | --- | --- | --- |
| MFHI | HI值→GPR | PASS | MULT后HI=0正确读出 |
| MFLO | LO值→GPR | PASS | MULT后LO=50正确读出 |
| MTHI | GPR→HI | PASS | 0x42→HI |
| MTLO | GPR→LO | PASS | 0x42→LO |

**数据移动覆盖率: 4/4 (100%)**

### 3.6 自陷指令 (2条)

| 指令 | 测试内容 | 状态 | 备注 |
| --- | --- | --- | --- |
| SYSCALL | 触发SystemCall例外 | PASS | PC→0xBFC00380 |
| BREAK | 触发Breakpoint例外 | PASS | |

**自陷指令覆盖率: 2/2 (100%)**

### 3.7 访存指令 (8条)

| 指令 | 测试内容 | 状态 | 备注 |
| --- | --- | --- | --- |
| LW | 读32位字 | PASS | |
| LB | 读字节(有符号扩展) | PASS | 0x78→0x00000078 |
| LBU | 读字节(无符号扩展) | PASS | |
| LH | 读半字(有符号扩展) | PASS | |
| LHU | 读半字(无符号扩展) | PASS | |
| SB | 写字节 | PASS | |
| SH | 写半字 | PASS | |
| SW | 写32位字 | PASS | |

**访存指令覆盖率: 8/8 (100%)**

### 3.8 特权指令 (3条)

| 指令 | 测试内容 | 状态 | 备注 |
| --- | --- | --- | --- |
| MFC0 | 读CP0寄存器 | PASS | |
| MTC0 | 写CP0寄存器 | PASS | |
| ERET | 例外返回 | PASS | PC←EPC |

**特权指令覆盖率: 3/3 (100%)**

---

## 4. 冒险验证

### 4.1 数据冒险 — 前递 (Forwarding)

| 冒险类型 | 测试场景 | 状态 |
| --- | --- | --- |
| EX前递(1-cycle) | ADD $1,$2,$3; SUB $4,$1,$5 | PASS |
| MEM前递(2-cycle) | ADD $1,$2,$3; NOP; SUB $4,$1,$5 | PASS |
| Load-Use Stall | LW $1,0($2); ADD $3,$1,$4 | PASS |

### 4.2 控制冒险

| 场景 | 测试 | 状态 |
| --- | --- | --- |
| Always Taken(正确) | 分支实际跳转 | PASS |
| Always Taken(错误) | 分支实际不跳转(流水线冲刷) | PASS |
| 延迟槽指令 | 分支指令+NOP延迟槽 | PASS |
| JR跳转 | 寄存器跳转 | PASS |

---

## 5. 例外处理验证

| 例外类型 | 测试 | 状态 |
| --- | --- | --- |
| SystemCall | SYSCALL指令触发 | PASS |
| Breakpoint | BREAK指令触发 | PASS |
| Overflow | ADD溢出触发 | PASS |
| ReservedInstr | 未定义指令触发 | PASS |
| AddressError(Load) | LW未对齐地址 | PASS |
| AddressError(Store) | SW未对齐地址 | PASS |

---

## 6. 覆盖率统计

### 6.1 指令覆盖率

| 类别 | 总数 | 覆盖 | 百分比 |
| --- | --- | --- | --- |
| 算术运算 | 14 | 14 | 100% |
| 逻辑运算 | 8 | 8 | 100% |
| 移位指令 | 6 | 6 | 100% |
| 分支跳转 | 12 | 12 | 100% |
| 数据移动 | 4 | 4 | 100% |
| 自陷指令 | 2 | 2 | 100% |
| 访存指令 | 8 | 8 | 100% |
| 特权指令 | 3 | 3 | 100% |
| **总计** | **57** | **57** | **100%** |

### 6.2 功能覆盖率

| 功能点 | 状态 |
| --- | --- |
| 数据前递 EX→EX | COVERED |
| 数据前递 MEM→EX | COVERED |
| Load-Use Stall | COVERED |
| 分支预测 Always Taken | COVERED |
| 分支预测错误恢复 | COVERED |
| 延迟槽执行 | COVERED |
| 例外入口/返回 | COVERED |
| CP0寄存器读写 | COVERED |
| 立即数符号/零扩展 | COVERED |
| 字节/半字/字访问 | COVERED |

---

## 7. 波形截图说明

仿真波形文件: `cpu_yellow_top_tb.vcd`

关键观察信号：
- PC: 程序计数器变化
- instr: 取指指令
- ALU结果: ALU运算输出
- 寄存器写使能/写数据
- 存储器读写信号
- 前递控制信号
- 流水段间寄存器

---

## 8. 已知问题与限制

1. **多周期乘除法**: 当前实现中 MULT/DIV 在单周期内完成，实际硬件可能需要多周期
2. **CP0 寄存器**: 仅实现了 Status, Cause, EPC 三个寄存器
3. **中断**: 中断信号接口已预留，但完整的中断控制器未实现
4. **Cache**: 未实现指令/数据 Cache
5. **分支预测错误处理**: 当前对 BGEZ/BLTZ 等指令的预测错误处理在 ID 阶段完成，BEQ/BNE 在 EX 阶段完成

---

## 9. 结论

CPU_YELLOW 处理器完成了全部 57 条 MIPS 指令的设计与验证，五级流水线结构正确，数据前递和冒险检测机制工作正常，例外处理路径正确。所有指令测试用例通过，指令覆盖率达到 100%。
