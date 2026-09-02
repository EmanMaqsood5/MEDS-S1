# Full AXI4 Register Protocol Shell

This is the full AXI4 counterpart to the AXI4-Lite register shell. It has the same general shape (one module per channel, wired together into a shell that exposes a plain Wr*/Rd* register boundary) but now handles bursts: multiple beats per transaction, WLAST/RLAST, and INCR/FIXED/WRAP addressing, instead of the single beat AXI4-Lite deals with.

## The idea

AXI4-Lite only ever moves one address and one data word per transaction. Full AXI4 allows a burst of up to 16 beats behind a single address phase, and that burst can step through memory in different ways (INCR just walks forward, FIXED stays on the same address every beat, WRAP wraps back around a power of two aligned window, which is what a cache line refill or write back typically uses). This package captures a burst's address and burst descriptor once, then walks the state machine one beat at a time, generating the correct next address each beat and only responding once the whole burst is done (for writes) or once each beat's own response is ready (for reads, since AXI4 gives a response per beat rather than per burst).

Everything downstream, the register content module behind the Wr*/Rd* boundary, still just sees one WrEn pulse per beat or one RdAddr lookup per beat. It does not need to know a burst is happening at all.

## Files

**axi4_params.svh**
Widths and constants for the full AXI4 backbone: 40 bit address, 256 bit data, derived strobe width, 6 bit native ID width, plus the wider slave facing ID width used behind a crossbar, and a max burst length of 16 beats with the small counter width needed to count them.

**meds_s1_axi4_aw_ch.sv**
Write address channel capture. Same IDLE/CAPTURED shape as the AXI4-Lite version, but now also captures ID, burst length (AWLEN), size (AWSIZE), and burst type (AWBURST) alongside the address, since the rest of the burst depends on all four. Holds the whole burst descriptor stable until AwConsume fires, which only happens once the last beat has committed.

**meds_s1_axi4_w_ch.sv**
Write data channel capture. Captures one beat of data, strobe, and WLAST at a time. Because a burst has several beats, this buffer gets drained and refilled once per beat by meds_s1_axi4_b_ch, which is the module that actually tracks how many beats have gone by.

**meds_s1_axi4_b_ch.sv**
The write response channel, and the module that owns the whole write burst sequence. For each beat it waits for meds_s1_axi4_w_ch to have data ready, drives WrAddr/WrData/WrStrb and pulses WrEn once, remembers whether that beat's address was in range, then advances the address for the next beat (holds it constant for FIXED, adds the transfer size for INCR, wraps back to an aligned boundary for WRAP). Once AWLEN+1 beats have all committed, it raises BVALID with a single response: OKAY only if every beat in the burst was in range, DECERR if even one beat missed, since AXI4 only allows one write response per burst.

**meds_s1_axi4_ar_ch.sv**
Read address channel capture. Mirrors meds_s1_axi4_aw_ch: captures ID, address, length, size, and burst type when ARVALID fires, holds them until ArConsume clears the buffer.

**meds_s1_axi4_r_ch.sv**
The read data channel, and the module that owns the read burst sequence. For each beat it presents the current address to the content boundary, looks at the combinational RdData/RdAddrValid response, and returns that beat's data with its own RRESP, since unlike writes, AXI4 read responses are per beat, not per burst, so one out of range beat in the middle of a burst DECERRs just that beat and the burst carries on. RLAST is asserted only on the final beat. Address stepping for INCR/FIXED/WRAP works the same way as in meds_s1_axi4_b_ch.

**meds_s1_axi4_reg_protocol.sv**
The top level shell, wiring the five channel modules above together the same way meds_s1_axil_reg_protocol.sv does for AXI4-Lite. Exposes the standard AXI4 burst capable ports (with awlen/awsize/awburst, wlast, arlen/arsize/arburst, rlast) on one side, and the same simple Wr*/Rd* register boundary as the AXI4-Lite shell on the other, just now pulsed once per beat instead of once per transaction. This module can be wired directly onto a crossbar's slave port, or used anywhere a full AXI4 (not AXI4-Lite) slave interface is needed.

**meds_s1_axi4_slave_wrapper.sv**
A concrete example peripheral built on top of meds_s1_axi4_reg_protocol.sv: a small, fixed register map (ID, VERSION, CTRL, STATUS, IRQ_STATUS, CAPABILITY, PERF_CYCLES, PERF_STALLS) meant to be the standard control/status block a hardware accelerator or similar block would expose. CTRL writes generate one cycle HwStart/HwAbort pulses and set an interrupt enable bit. IRQ_STATUS is write-1-to-clear. Everything outside the mapped 0x20 byte block returns DECERR. Because it sits behind meds_s1_axi4_reg_protocol, a multi-beat burst just walks across these registers one beat at a time exactly like a sequence of single-beat accesses would.

**tb_axi4_simple.sv**
A directed smoke test of meds_s1_axi4_slave_wrapper. It drives a 4-beat INCR write burst across ID/VERSION/CTRL/STATUS, where only the CTRL beat actually lands on a writable register, so the other three beats exercise the per-beat DECERR path and the overall response comes back DECERR since AXI4 only gives one write response for the whole burst. It then drives a 4-beat INCR read burst over the same four registers and checks each beat's data, response, and that RLAST is only set on the last of the four beats. A full cycle by cycle trace of every AXI signal is printed throughout, in the same style as the earlier testbenches.

## How a write burst flows through the design

1. meds_s1_axi4_aw_ch captures the address, ID, length, size, and burst type for the whole burst.
2. meds_s1_axi4_w_ch captures one beat of data and strobe at a time.
3. meds_s1_axi4_b_ch pulls a beat's data together with the current beat address, pulses WrEn, checks if that address was valid, then works out the next beat's address based on the burst type.
4. Once the last beat (AWLEN+1 total) has committed, meds_s1_axi4_b_ch raises BVALID with a single OKAY or DECERR covering the whole burst.

## How a read burst flows through the design

1. meds_s1_axi4_ar_ch captures the address, ID, length, size, and burst type.
2. meds_s1_axi4_r_ch presents the current beat's address to the content boundary, reads back RdData/RdAddrValid, and raises RVALID with that beat's own RRESP.
3. Once RREADY accepts a beat, meds_s1_axi4_r_ch advances to the next beat's address (or asserts RLAST and returns to IDLE if that was the last beat).
