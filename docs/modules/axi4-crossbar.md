# AXI4 Crossbar

This set of files builds an M by N AXI4 crossbar, the piece that sits between several masters (CPU pipeline, DMA, debug port, and so on) and several slaves (memory, peripherals, the AXI4-Lite bridge), decoding addresses and arbitrating so any master can reach any slave.

## The idea

Every master's address channel gets decoded against a project specific memory map to figure out which slave it wants. Multiple masters wanting the same slave at once get arbitrated round robin, one write burst and one read burst in flight per slave at a time. Responses coming back from a slave need to find their way back to whichever master actually issued the request, which the crossbar does by tagging each request's ID with the master's index on the way out and stripping that tag back off on the way back. Any address that does not match anything in the memory map gets handed to a small dedicated module that fabricates a legal DECERR response instead of leaving the master hanging forever.

## Files

**axi4_params.svh**
Backbone widths and the master and slave counts: 40 bit address, 256 bit data, 6 bit native ID, 6 masters, 6 slaves, plus the small index widths needed to encode a master or slave index, and the wider slave facing ID width formed by prepending the master index tag onto the native ID.

**axi4_addr_map.svh**
The actual memory map: base address and size for each region, in priority order, along with which slave index each region routes to. This is the one file meant to be edited per project, everything else in the package just reads out of it.

**meds_s1_axi4_addr_decode.sv**
Combinational address decode. Takes an address, checks it against every region in axi4_addr_map.svh in priority order, and returns the matching slave index plus a hit flag. If nothing matches, hit is deasserted so the crossbar can route that access to the DECERR sink instead of a real slave.

**meds_s1_rr_arbiter.sv**
A generic round robin arbiter for N requesters. Give it a vector of request bits and a pulse saying a grant was consumed, and it hands back a one-hot grant, the winning index, and whether anything was granted at all. After a grant is consumed, priority rotates so the just-granted requester moves to the back of the line, which is what keeps multiple masters contending for the same slave from starving each other.

**meds_s1_axi4_decerr_sink.sv**
The fallback slave for addresses that miss the memory map entirely. Without this, a master addressing an unmapped region would never see its address channel accepted anywhere and would simply hang, since a decode miss never enters the normal per-slave arbitration. This module instead accepts the address immediately (there is no real bandwidth being contended for), drains any write data beats without doing anything with them, and returns a DECERR response, replaying it once per beat on a read burst so a multi-beat burst to nowhere still gets a complete, protocol legal burst back rather than a truncated one.

**meds_s1_axi4_crossbar.sv**
The crossbar itself. Runs meds_s1_axi4_addr_decode per master to figure out which slave each request wants, then for each slave runs a pair of round robin arbiters (one for writes, one for reads) among the masters that decoded to it. Only one AW and its trailing W burst, and one AR and its trailing R burst, are allowed in flight per slave at a time, matching a single outstanding transaction assumption on the master side. IDs are widened on the way into a slave by prepending the winning master's index as a tag, and responses coming back are routed to the correct master by reading that tag back out of the returned ID and stripping it off before handing the response back. Any master whose address missed the memory map is instead wired to meds_s1_axi4_decerr_sink so it always gets a well formed response instead of hanging, and a decerr_pulse output flags when that happens for debug or performance counting purposes.

**meds_s1_axi4_top_cfg_slave.sv**
A small piece of top level glue showing how to actually hang a real peripheral off one of the crossbar's slave ports. It instantiates meds_s1_axi4_slave_wrapper (the example CTRL/STATUS style register block from the plain AXI4 package) on slave index 3, one of the peripheral MMIO windows, and does the address translation the crossbar itself does not do: the crossbar hands a slave the same full backbone address the master issued, so this module subtracts that slave's base address before handing the request down to meds_s1_axi4_slave_wrapper, whose internal register offsets are all relative to 0.

## Testbenches

**tb_axi4_crossbar.sv**
An end to end testbench for the whole crossbar. Every one of the six slave ports is driven by a small behavioral AXI4 memory model (simple_axi4_mem_slave, not part of the design) so the crossbar has something real to talk to everywhere, and master side driver tasks issue single or multi-beat writes and reads from any chosen master index. It walks through: a basic single beat write and read-back, a multi-beat INCR burst, ID tag routing checked by having two different masters use the same AXI ID value to two different slaves and confirming each response finds its way back to the right master, arbitration between two masters contending for the same slave, the DECERR path for an address outside the memory map, a full sweep of every master against every mapped region, and a final stress test where all six masters fire multi-beat bursts at six different slaves at once.

**tb_axi4_decerr_sink.sv**
A focused conformance test for meds_s1_axi4_decerr_sink on its own. Covers a single beat write miss, a multi-beat write miss (checking the sink drains every write beat before it ever raises its response, so the response can't jump ahead of the burst), a single beat read miss, a multi-beat read miss (checking RLAST only lands on the true final beat of the replayed burst), back to back misses on the same master lane to prove the internal state machine returns cleanly to idle, and two different master lanes missing at the same time, one on the write side and one on the read side, to prove the lanes are fully independent of each other.
