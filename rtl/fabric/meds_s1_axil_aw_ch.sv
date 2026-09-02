

`include "parameters.svh"

module meds_s1_axil_aw_ch (
    input  logic                        Aclk,
    input  logic                        Aresetn,

    input  logic [`ADDR_WIDTH-1:0]      Awaddr,
    input  logic                        Awvalid,
    output logic                        Awready,

    output logic [`ADDR_WIDTH-1:0]      AwCapturedAddr,
    output logic                        AwCaptured,
    input  logic                        AwConsume   // pulse: clear the buffer
);

    localparam [0:0] IDLE     = 1'd0,
                      CAPTURED = 1'd1;

    reg                     state, state_n;
    reg [`ADDR_WIDTH-1:0]  addr_reg, addr_reg_n;

    always @(posedge Aclk or negedge Aresetn) begin
        if (!Aresetn) begin
            state    <= IDLE;
            addr_reg <= 0;
        end else begin
            state    <= state_n;
            addr_reg <= addr_reg_n;
        end
    end

    always @(*) begin
        state_n    = state;
        addr_reg_n = addr_reg;

        Awready = 1'b0;

        case (state)

            IDLE: begin
                Awready = 1'b1;
                if (Awvalid) begin
                    addr_reg_n = Awaddr;
                    state_n    = CAPTURED;
                end
            end

            CAPTURED: begin
                Awready = 1'b0;
                if (AwConsume) state_n = IDLE;
            end

            default: state_n = IDLE;
        endcase
    end

    assign AwCapturedAddr = addr_reg;
    assign AwCaptured     = (state == CAPTURED);

endmodule
