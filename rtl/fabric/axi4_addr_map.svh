
`ifndef AXI4_ADDR_MAP_SVH
`define AXI4_ADDR_MAP_SVH

localparam int ADDR_MAP_NUM_REGIONS = 6;

// base address, per region, in priority order (first match wins)
localparam logic [`AXI_ADDR_W-1:0] ADDR_MAP_BASE [ADDR_MAP_NUM_REGIONS] = '{
    40'h00_0000_1000,  // 0  SLAVE0 boot/rom               32K
    40'h00_1000_0000,  // 1  SLAVE5 peripheral region      256M
    40'h00_2000_0000,  // 2  SLAVE3 peripheral MMIO A       64K
    40'h00_2001_0000,  // 3  SLAVE4 peripheral MMIO B       64K
    40'h00_4000_0000,  // 4  SLAVE1 on-chip SRAM           256K
    40'h00_8000_0000    // 5  SLAVE2 DRAM / main memory       1G
};

localparam logic [`AXI_ADDR_W-1:0] ADDR_MAP_SIZE [ADDR_MAP_NUM_REGIONS] = '{
    40'h0000_8000,      // 0  32K
    40'h1000_0000,      // 1  256M
    40'h0001_0000,      // 2  64K
    40'h0001_0000,      // 3  64K
    40'h0004_0000,      // 4  256K
    40'h8000_0000       // 5  1G
};

// which of the crossbar's slave ports this region routes to
localparam logic [`SIDX_W-1:0] ADDR_MAP_SLV_SEL [ADDR_MAP_NUM_REGIONS] = '{
    3'd0,  // boot/rom          -> SLAVE0
    3'd5,  // peripherals       -> SLAVE5 (AXI4-Lite bridge, sub-decoded downstream)
    3'd3,  // peripheral MMIO A -> SLAVE3
    3'd4,  // peripheral MMIO B -> SLAVE4
    3'd1,  // sram              -> SLAVE1
    3'd2   // dram              -> SLAVE2
};

`endif // AXI4_ADDR_MAP_SVH
