
`ifndef AXI4_PARAMS_SVH
`define AXI4_PARAMS_SVH

`define AXI_ADDR_W 40
`define AXI_DATA_W 256
`define AXI_STRB_W (`AXI_DATA_W/8)
`define AXI_ID_W 6

`define NUM_MASTERS 6 // 0:MASTER0 1:MASTER1 2:MASTER2 3:MASTER3 4:MASTER4 5:MASTER5 (Debug/Sys)
`define NUM_SLAVES 6 // 0:SLAVE0 (Boot/ROM) 1:SLAVE1 (SRAM) 2:SLAVE2 (DRAM) 3:SLAVE3 (Peripheral MMIO A) 4:SLAVE4 (Peripheral MMIO B) 5:SLAVE5 (AXI4-Lite bridge)

// log2 helpers
`define MIDX_W 3 
`define SIDX_W 3


`define AXI_SID_W (`AXI_ID_W + `MIDX_W)

// Burst counters (: INCR <= 16 beats, WRAP for refill)
`define AXI_MAX_BEATS 16
`define AXI_BEAT_CNT_W 4 

`endif 
