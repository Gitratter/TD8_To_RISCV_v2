# TD8_To_RISCV_v2 検証記録

## 1. 検証対象

- v1.1取得元: `Gitratter/TD8_To_RISCV_v1.1` / `main`
- v1.1基準commit: `27bebc9847ef0f8d192b80ecb6754cc1005dde61`
- v2検証日: 2026-09-04
- RTL top: `TD4_TOP`
- ISA範囲: 非特権RV32I基本40命令

GitHub上のrepositoryには書き込まず，取得したv1.1を基準としてローカルの`TD8_To_RISCV_v2`だけを検証した。

## 2. 使用tool

| tool | version / option |
|---|---|
| Icarus Verilog | 14.0 (devel) |
| RTL mode | `-g2012 -Wall` |
| test形式 | self-checking SystemVerilog，失敗時`$fatal` |
| Yosys | 0.68，`synth_xilinx -family xc7` |

## 3. Parse／elaboration

`sources_1/new`の全Verilog sourceを対象に，次の条件でboard topをelaborationした。

```powershell
$rtl = (Get-ChildItem -LiteralPath ./sources_1/new -Filter *.v | Sort-Object Name).FullName
& iverilog -g2012 -Wall -s TD4_TOP -tnull $rtl
```

結果はPASSであり，errorおよびIcarusが報告するwarningは0件であった。

## 4. 自己検査simulation

`scripts/run_tests.ps1`から11個のtestbenchを連続実行した結果，全てPASSした。

| testbench | 主な検証内容 | 結果 |
|---|---|:---:|
| `tb_v2_decoder` | RV32Iの40命令名を各1 encoding以上decodeし，legal countが40であること。MUL，予約`funct`，不正shift，FENCE.I，CSR等13 encodingを拒否し，副作用制御が0であること | PASS |
| `tb_v2_immediates` | I／S／B／U／J immediateの正負encoding範囲端と符号拡張 | PASS |
| `tb_v2_integer` | OP 10種，OP-IMM 9種，LUI，AUIPC，FENCE。signed／unsigned比較，shift量31および`rs2[4:0]`，即値符号拡張，`x0`書込み抑止 | PASS |
| `tb_v2_boundaries` | ADD／SUB／ADDIのmodulo-2^32 overflow，I-immediate両端，FENCE rw,rw，`JALR rd=rs1` | PASS |
| `tb_v2_control_flow` | 6種のbranchのtaken／not-taken，forward／backward branch，JAL，negative-offset JAL，JALR，link値 | PASS |
| `tb_v2_memory` | LB，LH，LW，LBU，LHU，SB，SH，SW，全byte lane，両halfword lane，little-endian，符号／zero拡張 | PASS |
| `tb_v2_memory_boundaries` | 負のload/store offset，RAM末端のbyte `0xff`，halfword `0xfe`，word `0xfc` | PASS |
| `tb_v2_mmio` | input MMIOのLWと8bit値のzero拡張，output MMIOのSW，output registerのLW readback | PASS |
| `tb_v2_faults` | 20 case。illegal，ECALL，EBREAK，fetch／target／load／storeのalignmentおよびaccess fault，`load rd=x0`，word-only MMIO，fault時のPC／RF／RAM／output副作用抑止 | PASS |
| `tb_v2_lutram_reset` | Data RAM内容のreset跨ぎ保持，Register File物理配列の非reset，valid maskだけのreset，reset中の全commit抑止 | PASS |
| `tb_v2_board` | 既定ROM，switch入力`0x05`からLED出力`0xbe`，7 segment `E`，anode `1110`，retire count `8`，faultなし | PASS |

実行commandは次のとおりである。

```powershell
./scripts/run_tests.ps1
```

各testbenchは，対象命令の最終Register値，Program Counter，memory lane，trap cause/valueまたはboard portを期待値と比較する。単にwaveformを目視した結果ではない。

## 5. v1.1資源最適化の機能回帰

v2のDataMemoryは引き続き単一の`reg [31:0] memory [0:63]`であり，clocked processにreset分岐を持たない。Register Fileは2 read operandのため同内容の32×32bit配列を2個持つが，両配列にもreset代入を行わず，32bitの`valid`だけをresetする。

`tb_v2_lutram_reset`では，Register FileとData RAMへ値を書いた後にresetをassertし，次を確認した。

- x1の物理RAM内容は`0x55`のままである。
- `valid`は0へclearされるため，architecturalなx1 readは0になる。
- Data RAM word 0は`0x55`のままである。
- reset中にPC=0へstore命令を置き`cpu_enable=1`としても，`commit_enable=0`によりRAMは変化しない。

これはreset semanticsと副作用抑止のsimulation確認である。Vivadoが実際にLUTRAM primitiveへ推論したことの証明ではない。

## 6. Yosysによる汎用合成check

`TD4_TOP`を対象にYosys 0.68の`check -assert`および`Xilinx 7-series`向けgeneric synthesisを実行し，PASSした。再実行用scriptは`scripts/yosys_synth_check.ys`である。

| 項目 | Yosys 0.68結果 |
|---|---:|
| design problems (`check -assert`) | 0 |
| DataMemory `RAM64X1S` | 32 |
| Register File `RAM32M` | 12 |
| `RAMB18E1` / `RAMB36E1` | 0 / 0 |
| FDCE | 141 |
| estimated logic cells | 1186 |

この結果から，production topでDataMemoryとRegister FileがFF配列へ全面展開されず，Yosysではdistributed-RAM primitiveへ写像されることを確認した。ただしprimitive packing，logic最適化および資源数は合成toolに依存する。Yosysの`1186 estimated logic cells`やprimitive数を，VivadoのSlice LUT／LUTRAM値または配置配線後結果として流用してはならない。

実行commandは次のとおりである。

```powershell
./scripts/run_yosys_check.ps1
```

## 7. 未実施項目と判定上の注意

本成果物では次を未実施とした。

- Vivado synthesis／implementation／bitstream生成
- Vivado `report_ram_utilization`によるRAM64／RAM32 primitiveの確認
- VivadoによるLUT，FF，LUTRAM，BRAM，WNS，TNS，WHSおよびWPWSのv2実測
- 実機Basys 3での動作確認
- RISC-V architectural test suiteまたはformal verification

したがって，v1.1の`LUT=702`，`FF=126`，`LUTRAM=76`およびtiming値をv2の結果として扱ってはならない。v2について現時点で主張できるのは，「RV32I基本40命令をRTLへ実装し，付属project testbenchが全てPASSし，Yosys generic synthesisでdistributed-RAM構造を確認した」ことまでである。

Vivadoでは旧runを流用せず，`TD4_TOP`をtop，`xc7a35tcpg236-1`をpart，XDCのclock periodを10 nsとしてfresh synthesis／implementationを行う。完了後，open project内で`scripts/vivado_reports.tcl`をsourceすると，階層別資源，RAM推論，timingおよびpower reportを`reports/v2`へ保存できる。
