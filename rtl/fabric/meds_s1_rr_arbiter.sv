

`include "axi4_params.svh"

module meds_s1_rr_arbiter #(
    parameter int N = `NUM_MASTERS
) (
    input logic clk_i,
    input logic rst_ni,
    input logic [N-1:0] req,
    input logic advance, // pulse: grant consumed, rotate priority
    output logic [N-1:0] grant, // one-hot
    output logic [$clog2(N)-1:0] grant_idx,
    output logic grant_valid
);
    logic [N-1:0] mask;
    logic [N-1:0] req_masked;
    logic [N-1:0] grant_masked, grant_unmasked;

    assign req_masked = req & mask;

    // priority encoders, plain:lowest index still asking wins.
    
    always_comb begin
        grant_masked = '0;
        for (int i = 0; i < N; i++) begin
            if (req_masked[i] && (grant_masked == '0)) grant_masked[i] = 1'b1;
        end
    end

    always_comb begin
        grant_unmasked = '0;
        for (int i = 0; i < N; i++) begin
            if (req[i] && (grant_unmasked == '0)) grant_unmasked[i] = 1'b1;
        end
    end

    assign grant = (|grant_masked) ? grant_masked : grant_unmasked;
    assign grant_valid = |req;

    always_comb begin
        grant_idx = '0;
        for (int i = 0; i < N; i++) if (grant[i]) grant_idx = i[$clog2(N)-1:0];
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) mask <= '1;
        else if (advance && grant_valid) begin
            // next priority starts just after the master that was just granted
            mask <= '0;
            for (int i = 0; i < N; i++)
                if (i > grant_idx) mask[i] <= 1'b1;
        end
    end
endmodule
