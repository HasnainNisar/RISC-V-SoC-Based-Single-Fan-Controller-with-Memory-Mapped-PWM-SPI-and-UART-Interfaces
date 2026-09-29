#!/usr/bin/env python3
"""gen_programs.py - generates the project's hex programs.

  test_program.hex     system test: SRAM, PWM, config-SRAM read, SPI profile loading,
                       UART TX + RX, unmapped access  (used by tb_soc_top and the UVM env)
  instr_test.hex       full RV32I instruction test, stores one result word per check to DMEM
  instr_expected.hex   golden results from the independent ISS (first line = word count)

Run from anywhere:  python3 tools/gen_programs.py
Output goes to the project root AND sim/ (the simulator's cwd is the project root).
"""
import os, sys, subprocess, shutil, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from rv32i_tools import Asm, Iss

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# ======================================================================
# 1) System test program
# ======================================================================
def build_system_program():
    a = Asm()
    a.lui(1, 0x10000)                 # x1 = DMEM base 0x1000_0000
    # ---- SRAM write/read
    a.addi(2, 0, 123); a.sw(2, 1, 0); a.lw(3, 1, 0)               # DMEM[0] = 123
    # ---- PWM: duty=128, enable
    a.lui(4, 0x30000); a.addi(5, 0, 128); a.sw(5, 4, 4)
    a.addi(6, 0, 1);   a.sw(6, 4, 0)
    # ---- Config SRAM read (preloaded PROFILE_ID at offset 0x10) -> DMEM[5]
    a.lui(18, 0x20000); a.lw(19, 18, 16); a.sw(19, 1, 20)
    # ---- SPI profile loading: 4 transfers; rx byte -> DMEM[1..4] and CONFIG SRAM[0..3]
    a.lui(7, 0x30001); a.addi(8, 0, 0xA5); a.sw(8, 7, 4)          # SPI_TXDATA = 0xA5
    a.addi(20, 0, 0); a.addi(21, 0, 16)
    a.label("spi_next")
    a.addi(9, 0, 1); a.sw(9, 7, 0)                                 # SPI_CTRL.START
    a.label("spi_wait")
    a.lw(10, 7, 12); a.andi(11, 10, 1); a.bne(11, 0, "spi_wait")   # wait !BUSY
    a.lw(12, 7, 8)                                                 # SPI_RXDATA
    a.add(22, 1, 20); a.sw(12, 22, 4)                              # DMEM[1+i]
    a.add(23, 18, 20); a.sw(12, 23, 0)                             # CFG[i]  (profile load)
    a.addi(20, 20, 4); a.bne(20, 21, "spi_next")
    # ---- UART: enable TX+RX, send 'A', wait TX done, wait for RX byte from terminal
    a.lui(13, 0x30002); a.addi(14, 0, 3); a.sw(14, 13, 0)
    a.addi(15, 0, 0x41); a.sw(15, 13, 4)
    a.label("uart_wait")
    a.lw(16, 13, 12); a.andi(17, 16, 1); a.bne(17, 0, "uart_wait")     # TX_BUSY
    a.label("rx_wait")
    a.lw(16, 13, 12); a.andi(17, 16, 2); a.beq(17, 0, "rx_wait")       # RX_VALID
    a.lw(24, 13, 8); a.sw(24, 1, 24)                                   # DMEM[6] = received byte
    # ---- Unmapped access: write + read from 0x4000_0000 -> bus_error, rdata = 0xDEADBEEF
    a.lui(25, 0x40000); a.sw(0, 25, 0); a.lw(26, 25, 0); a.sw(26, 1, 28)   # DMEM[7]
    a.label("halt"); a.jal(0, "halt")
    return a

# ======================================================================
# 2) Full RV32I instruction test
# ======================================================================
def build_instr_program():
    a = Asm(); k = [0]; lbl = [0]
    def sig(reg):
        a.sw(reg, 1, 4 * k[0]); k[0] += 1
    def fresh():
        lbl[0] += 1; return f"L{lbl[0]}"
    a.li(1, 0x10000000)                 # x1 = DMEM base
    a.addi(2, 1, 400)                   # x2 = scratch area (word 100..)

    # ---- R-type (10 ops x 3 operand pairs) ----
    for va, vb in [(0xFFFFFFF0, 5), (0x12345678, 0x9ABCDEF3), (0x80000000, 0x0000001F)]:
        a.li(5, va); a.li(6, vb)
        for op in ("add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"):
            getattr(a, op)(7, 5, 6); sig(7)
    # ---- I-type ALU ----
    a.li(5, 0xFFFFFF85)                 # -123
    for op, imm in (("addi", 100), ("slti", 0), ("slti", -200), ("sltiu", -1), ("xori", 0x555),
                    ("ori", 0x0F0), ("andi", 0x0FF)):
        getattr(a, op)(7, 5, imm)
        sig(7)
    a.sltiu(7, 0, 1); sig(7)
    for op, sh in (("slli", 4), ("slli", 31), ("srli", 4), ("srai", 4), ("srai", 31)):
        getattr(a, op)(7, 5, sh); sig(7)
    # ---- LUI / AUIPC / x0 / FENCE ----
    a.lui(7, 0xABCDE); sig(7)
    a.auipc(7, 0x12345); sig(7)
    a.addi(0, 0, 55); sig(0)                                  # x0 must stay 0
    a.fence(); a.li(7, 0x1234); sig(7)
    # ---- Loads / stores (byte, half, word; signed/unsigned) ----
    a.li(5, 0x8081FF7F); a.sw(5, 2, 0)
    for off in range(4): a.lb(7, 2, off);  sig(7)
    for off in range(4): a.lbu(7, 2, off); sig(7)
    for off in (0, 2):   a.lh(7, 2, off);  sig(7)
    for off in (0, 2):   a.lhu(7, 2, off); sig(7)
    a.lw(7, 2, 0); sig(7)
    a.sw(0, 2, 4)                                            # SB into a zeroed word, all 4 lanes
    for i, v in enumerate((0x11, 0xA2, 0x33, 0xC4)):
        a.li(5, v); a.sb(5, 2, 4 + i)
    a.lw(7, 2, 4); sig(7)
    a.sw(0, 2, 8)                                            # SH, both halves
    a.li(5, 0xBEEF); a.sh(5, 2, 8); a.li(5, 0x1234); a.sh(5, 2, 10)
    a.lw(7, 2, 8); sig(7)
    a.li(5, 0xFFFFFFFF); a.sw(5, 2, 12)                      # narrow stores must not clobber neighbours
    a.sb(0, 2, 13); a.lw(7, 2, 12); sig(7)
    a.sh(0, 2, 14); a.lw(7, 2, 12); sig(7)
    # ---- Branches: each taken and not-taken ----
    def br(op, va, vb):
        a.li(5, va); a.li(6, vb); a.addi(7, 0, 0)
        l = fresh(); getattr(a, op)(5, 6, l)
        a.addi(7, 7, 1); a.label(l); a.addi(7, 7, 2); sig(7)  # 2 = taken, 3 = not taken
    for op, va, vb in (("beq", 5, 5), ("beq", 5, 6), ("bne", 5, 6), ("bne", 5, 5),
                       ("blt", -1, 1), ("blt", 1, -1), ("blt", 3, 3), ("bge", 1, -1), ("bge", -1, 1), ("bge", 3, 3),
                       ("bltu", 1, -1), ("bltu", -1, 1), ("bgeu", -1, 1), ("bgeu", 1, -1), ("bgeu", 7, 7)):
        br(op, va & 0xFFFFFFFF, vb & 0xFFFFFFFF)
    a.li(5, 0); a.li(6, 5)                                    # backward branch loop
    a.label("bloop"); a.addi(5, 5, 1); a.bne(5, 6, "bloop"); sig(5)
    # ---- JAL / JALR ----
    a.addi(7, 0, 7); l = fresh(); a.jal(8, l); a.addi(7, 0, 99); a.label(l); sig(8); sig(7)
    for adj in (16, 17):                                     # 17: JALR must clear bit 0
        a.addi(7, 0, 5)
        a.auipc(9, 0); a.addi(9, 9, adj); a.jalr(10, 9, 0)
        a.addi(7, 0, 99)                                     # skipped
        sig(10); sig(7)
    a.label("halt"); a.jal(0, "halt")
    return a, k[0]

# ======================================================================
def write_hex(path, text):
    with open(path, "w") as f: f.write(text)

def gnu_crosscheck(asm, name):
    """Assemble the same listing with the real GNU assembler and compare every word."""
    as_ = shutil.which("riscv64-unknown-elf-as"); oc = shutil.which("riscv64-unknown-elf-objcopy")
    if not as_ or not oc:
        print(f"  [{name}] GNU riscv binutils not found - cross-check skipped"); return
    inv = {}
    for l, pc in asm.labels.items(): inv.setdefault(pc, []).append(l)
    lines = [".text", ".globl _start", "_start:"]
    for i, (_, _, txt) in enumerate(asm.items):
        for l in inv.get(i * 4, []): lines.append(f"{l}:")
        lines.append("  " + txt)
    with tempfile.TemporaryDirectory() as d:
        s, o, b = (os.path.join(d, x) for x in ("t.s", "t.o", "t.bin"))
        open(s, "w").write("\n".join(lines) + "\n")
        subprocess.check_call([as_, "-march=rv32i", "-mabi=ilp32", "-mno-relax", s, "-o", o])
        subprocess.check_call([oc, "-O", "binary", "-j", ".text", o, b])
        data = open(b, "rb").read()
    gnu = [int.from_bytes(data[i:i+4], "little") for i in range(0, len(data), 4)]
    mine = asm.assemble()
    bad = [i for i, (x, y) in enumerate(zip(mine, gnu)) if x != y]
    assert len(mine) == len(gnu) and not bad, f"[{name}] mismatch vs GNU as at words {bad[:5]}"
    print(f"  [{name}] {len(mine)} words match the GNU assembler exactly")

def main():
    print("Generating programs ...")
    # ---- system program
    a = build_system_program()
    gnu_crosscheck(a, "test_program")
    text, words = a.hex_lines("// test_program.hex - GENERATED by tools/gen_programs.py (do not edit by hand)\n"
        "// System test: SRAM r/w, PWM setup, config-SRAM read, SPI profile loading (4 bytes -> DMEM[1..4] + CONFIG[0..3]),\n"
        "// UART TX 'A', UART RX (byte from terminal -> DMEM[6]), unmapped access (bus_error, DMEM[7]=0xDEADBEEF).\n")
    for d in (ROOT, os.path.join(ROOT, "sim")): write_hex(os.path.join(d, "test_program.hex"), text)
    print(f"  test_program.hex : {len(words)} instructions")

    # ---- instruction test + golden model
    a, nsig = build_instr_program()
    gnu_crosscheck(a, "instr_test")
    text, words = a.hex_lines("// instr_test.hex - GENERATED by tools/gen_programs.py (do not edit by hand)\n"
        "// Full RV32I instruction test. Results are stored to DMEM words 0..N-1.\n")
    iss = Iss(words); iss.run()
    exp = [iss.dmem_word(i) for i in range(nsig)]
    exp_txt = ("// instr_expected.hex - GENERATED golden results from tools/rv32i_tools.py (independent ISS)\n"
               f"{nsig:08X}  // number of result words that follow\n" +
               "".join(f"{v:08X}  // DMEM[{i}]\n" for i, v in enumerate(exp)))
    for d in (ROOT, os.path.join(ROOT, "sim")):
        write_hex(os.path.join(d, "instr_test.hex"), text); write_hex(os.path.join(d, "instr_expected.hex"), exp_txt)
    print(f"  instr_test.hex   : {len(words)} instructions, {nsig} checked result words")
    used = sorted({it[1][0] if it[0] in ('R','I','SH','LD','ST','B') else ('lui' if it[0]=='U' else it[0]) for it in a.items})
    print(f"  distinct instruction kinds exercised: {len(used)}")

if __name__ == "__main__":
    main()
