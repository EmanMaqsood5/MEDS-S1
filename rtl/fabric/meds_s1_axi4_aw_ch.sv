
`include "axi4_params.svh"

module meds_s1_axi4_aw_ch #(
    parameter int ID_W = `AXI_ID_W 
) (
    input logic clk_i,
    input logic rst_ni,

    input logic [ID_W-1:0] awid,
    input logic [`AXI_ADDR_W-1:0] awaddr,
    input logic [7:0] awlen,
    input logic [2:0] awsize,
    input logic [1:0] awburst,
    input logic awvalid,
    output logic awready,

    output logic [ID_W-1:0] AwCapturedId,
    output logic [`AXI_ADDR_W-1:0] AwCapturedAddr,
    output logic [7:0] AwCapturedLen,
    output logic [2:0] AwCapturedSize,
    output logic [1:0] AwCapturedBurst,
    output logic AwCaptured,
    input logic AwConsume // pulse: clear the buffer
);

    localparam [0:0] IDLE = 1'd0,
                      CAPTURED = 1'd1;

    logic state, state_n;
    logic [ID_W-1:0] id_reg, id_reg_n;
    logic [`AXI_ADDR_W-1:0] addr_reg, addr_reg_n;
    logic [7:0] len_reg, len_reg_n;
    logic [2:0] size_reg, size_reg_n;
    logic [1:0] burst_reg, burst_reg_n;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            id_reg <= '0;
            addr_reg <= '0;
            len_reg <= '0;
            size_reg <= '0;
            burst_reg <= '0;
        end else begin
            state <= state_n;
            id_reg <= id_reg_n;
            addr_reg <= addr_reg_n;
            len_reg <= len_reg_n;
            size_reg <= size_reg_n;
            burst_reg <= burst_reg_n;
        end
    end

    always_comb begin
        state_n = state;
        id_reg_n = id_reg;
        addr_reg_n = addr_reg;
        len_reg_n = len_reg;
        size_reg_n = size_reg;
        burst_reg_n = burst_reg;

        awready = 1'b0;

        case (state)

            IDLE: begin
                awready = 1'b1;
                if (awvalid) begin
                    id_reg_n = awid;
                    addr_reg_n = awaddr;
                    len_reg_n = awlen;
                    size_reg_n = awsize;
                    burst_reg_n = awburst;
                    state_n = CAPTURED;
                end
            end

            CAPTURED: begin
                awready = 1'b0;
                if (AwConsume) state_n = IDLE;
            end

            default: state_n = IDLE;
        endcase
    end

    assign AwCapturedId = id_reg;
    assign AwCapturedAddr = addr_reg;
    assign AwCapturedLen = len_reg;
    assign AwCapturedSize = size_reg;
    assign AwCapturedBurst = burst_reg;
    assign AwCaptured = (state == CAPTURED);

endmodule
