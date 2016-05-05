/********************************************************************************
 * masm.d: main file for mips assembler/disassembler                            *
 * 2016 - Ben Perlin                                                            *
 *******************************************************************************/
import std.algorithm: sort;
import std.array;
import std.exception;
import std.format;
import std.getopt;
import std.process;
import std.stdio;

import terminal; // from Adam Druppe's github

import mips;

int main(string[] args) {
    string startAddress = "0x0040_0000";
    string traceFilename;
    string inputFilename; /* use stdin if empty */

    auto helpInformation = getopt(args,
          std.getopt.config.passThrough,
          "start|s", &startAddress,
          "output-file|o", &traceFilename);

    if (helpInformation.helpWanted) {
        defaultGetoptPrinter("Usage msim [filename]", helpInformation.options);
        return 0;
    }

    if (args.length == 2) {inputFilename = args[1];}
    else if (args.length > 2) {
        stderr.writeln("Usage msim [filename]");
        return 1;
    }

    // if using file output for trace file
    File traceFile = stdout;
    if (traceFilename != "") {
        try {
            traceFile = File(traceFilename, "w");
        } catch (Throwable o) {
            stderr.writeln("Failed to open file: ", traceFilename);
            return 1;
        }
    }
   
    auto mips = new MIPS();
    try {
        assembleAndLoad(mips, inputFilename, startAddress);
    } catch (Exception except) {
        stderr.writeln("Error in assembler: ", except.msg);
        return 1;
    }

    mips.simulate();

    mips.showMemDump();

    return 0;
}

void assembleAndLoad(MIPS mips, string inputFile, string startAddress) {
    auto assemblerOutput = pipe();
    string[] args = ["./masm", "-s", startAddress];
    if (inputFile != "") args ~= inputFile; // otherwise use stdin

    auto apid = spawnProcess(args, stdin, assemblerOutput.writeEnd);
    scope(failure) wait(apid);

    uint address, binaryContents, hexContents;
    bool started = false;
    foreach (line; assemblerOutput.readEnd.byLine) {
        auto n = line.formattedRead("[0x%x] %b 0x%x", &address, &binaryContents, &hexContents);
        enforce(n == 3, "Expected three terms");

        enforce(binaryContents == hexContents, format("address [0x%08X]:"
              " binary and hex instructions do not match", address));

        enforce(!(address&3), format("address not word aligned, [0x%08X]", address));

        if (!started) {
            mips.PC = address;
            started = true;
        }

        mips.memory.store[address] = hexContents;
    }

    mips.exitPoint = address + 4;
    enforce (wait(apid) == 0);
}

/// quick and dirty printing utility
/// designed to function like an extension method (using UFCS)
void simulate(MIPS mips) {
    auto terminal = Terminal(ConsoleOutputType.cellular);
    auto input = RealTimeConsoleInput(&terminal, ConsoleInputFlags.raw);

    with (terminal) with (mips)
    while (!mips.finished) {
        mips.step(); // skip start state
        terminal.clear();
        
        writefln("Time: %d\t    Control-State: %s", time, control.state);
        writefln("PC: %s\tIR: %s\tMDR: %s\tA: %s\tB: %s\tALUout: %s", PC, IR, MDR, A, B, ALUout);
        writefln("Opcode: %s,\trs: $%d, \trt: $%d, \trd: $%d, \t shamt %d,\t funct: %s",
                 cast(Opcode) opcode, rs, rt, rd, shamt, cast(Funct) funct);
        writefln("immediate: 0x%08X,    address 0x%7X", immediate, address);

        writeln("\nControl-Signals:");
        writefln("    PCWrite: %b,    PCWriteCond: %b,    PCWriteCondNEQ: %b,    PCsource: %d",
                 control.PCWrite, control.PCWriteCond, control.PCWriteCondNEQ, control.PCsource);
        writefln("    IorD: %b, MemRead: %b, MemWrite %b, MemToReg: %b",
                 control.IorD, control.MemRead, control.MemWrite, control.MemToReg);
        writefln("    RegDest: %d, RegWrite: %b", control.RegDest, control.RegWrite);
        writefln("    ALUsrcA: %b, ALUsrcB: %d, ALUmasterOp: %s",
                 control.ALUsrcA, control.ALUsrcB, control.ALUmasterOp);

        writefln("\nALU: aluOp: %s,\talu: 0x%08x, zero: %b", aluControl, alu, zero);

        writeln("\nRegister-File:");
        foreach (i; 0..8) {
            enum fmt = "    $%-2d: 0x%08X".replicate(4);
            with (regFile) writefln(fmt, i, registers[i], i+8, registers[i+8],
                                    i+16, registers[i+16], i+24, registers[i+24]);
        }

        writeln("\nMemory Changes: ", memory.dirty ?
                format("[0x%08X] 0x%08X", memory.dirtyAddress, memory.dirtyData) : "");
        
        auto ch = input.getch(); // wait for input
        if (ch == 'q') break;
    }
}

void showMemDump(MIPS mips) {
    auto less = pipeProcess(["/usr/bin/less"], Redirect.stdin);

    less.stdin.writeln("Register-File:");
    foreach (i; 0..8) {
        enum fmt = "    $%-2d: 0x%08X".replicate(4);
        with (mips.regFile) less.stdin.writefln(fmt, i, registers[i], i+8, registers[i+8],
                                                i+16, registers[i+16], i+24, registers[i+24]);
    }
    less.stdin.writeln("\nMemory Dump\n[  address  ]\tcontents");
    
    foreach (pair; mips.memory.store.byKeyValue.array.sort!((a,b)=>(a.key < b.key))) {
        less.stdin.writefln("[0x%08X]\t0x%08X", pair.key, pair.value);
    }

    less.stdin.close();
    wait(less.pid);
}
