
`include "axi4_params.svh"
`include "axi4_addr_map.svh"

module meds_s1_axi4_addr_decode (
    input logic [`AXI_ADDR_W-1:0] addr,
    output logic [`SIDX_W-1:0] slv_sel,
    output logic hit
);

    logic [ADDR_MAP_NUM_REGIONS-1:0] region_hit;

    genvar gi;
    generate
        for (gi = 0; gi < ADDR_MAP_NUM_REGIONS; gi++) begin : g_region_hit
            assign region_hit[gi] = (addr >= ADDR_MAP_BASE[gi]) &&
                                     (addr < ADDR_MAP_BASE[gi] + ADDR_MAP_SIZE[gi]);
        end
    endgenerate

    always_comb begin
        slv_sel = '0;
        hit = 1'b0;
        for (int i = 0; i < ADDR_MAP_NUM_REGIONS; i++) begin
            if (region_hit[i] && !hit) begin
                slv_sel = ADDR_MAP_SLV_SEL[i];
                hit = 1'b1;
            end
        end
        if (!hit) slv_sel = 3'd5; // parked on the lite bridge port, gated by `hit` downstream
    end
endmodule
