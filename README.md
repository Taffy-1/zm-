# CPU_YELLOW - 五级流水线 MIPS 处理器

## 项目信息

- **课程名称:** 计算机组成与系统结构
- **课程编号:** U10M11007.02

## 项目概述

本项目设计了一款兼容 MIPS32 指令系统的五级流水线处理器，支持 57 条 MIPS 指令，具备完整的数据前递、冒险检测、分支预测、CP0 例外处理等功能。

## 文件结构

```
├── src/
│   ├── rtl/
│   │   ├── cpu_yellow_top.v       # 顶层模块
│   │   ├── if_stage.v             # 取指阶段
│   │   ├── id_stage.v             # 译码阶段
│   │   ├── ex_stage.v             # 执行阶段
│   │   ├── mem_stage.v            # 访存阶段
│   │   ├── wb_stage.v             # 写回阶段
│   │   ├── regfile.v              # 寄存器堆
│   │   ├── alu.v                  # 算术逻辑单元
│   │   ├── alu_control.v          # ALU控制单元
│   │   ├── control_unit.v         # 主控制单元
│   │   ├── hazard_detection.v     # 冒险检测单元
│   │   ├── forwarding_unit.v      # 数据前递单元
│   │   └── cp0.v                  # 协处理器0
│   └── tb/
│       └── cpu_yellow_top_tb.sv   # 仿真测试平台
├── doc/
│   ├── CPUYellow_spec.md          # 设计规格说明书
│   ├── CPUYellow_veri_rpt.md      # 验证报告
│   └── CPUYellow_report.md        # 个人总结报告
├── appendix/                       # 仿真截图、覆盖率报告等
└── README.md
```

## 编译运行步骤

### 使用 Verilator 仿真

```bash
# Lint check (ignore PINMISSING warnings from cp0_write_reg_o which is intentionally unconnected)
verilator --lint-only -Wno-PINMISSING src/rtl/*.v

# Compile and run simulation (--timing requires C++20 for coroutine support)
verilator --cc --exe --build -j 0 \
    -CFLAGS "-std=c++20" \
    src/rtl/*.v src/tb/cpu_yellow_top_tb.sv \
    --top-module cpu_yellow_top_tb \
    --timing \
    --trace

# Run
./obj_dir/Vcpu_yellow_top_tb

# With coverage
verilator --cc --exe --build -j 0 \
    --coverage \
    src/rtl/*.v src/tb/cpu_yellow_top_tb.sv \
    --top-module cpu_yellow_top_tb \
    --timing \
    --trace \
    -CFLAGS "-std=c++20"
```


# View waveform
gtkwave cpu_yellow_top_tb.vcd
```

## 设计特性

- **五级流水线:** IF → ID → EX → MEM → WB
- **57条MIPS指令:** 覆盖算术、逻辑、移位、分支跳转、数据移动、自陷、访存、特权指令
- **数据冒险处理:** 完全的前递(Forwarding) + Load-Use Stall
- **控制冒险处理:** Always Taken 分支预测 + 延迟槽支持
- **CP0 支持:** Status, Cause, EPC 寄存器 + 例外处理
- **存储器:** 哈佛架构，独立指令和数据存储器
