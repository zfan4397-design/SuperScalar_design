// Module-local replacements for the functions imported from config_pkg.sv.
// Intentionally no global include guard: each including module needs its own functions.
function fifoid_gt;
    input [`PRD_WIDTH:0] a;
    input [`PRD_WIDTH:0] b;
    begin
        fifoid_gt = ((a[`PRD_WIDTH] == b[`PRD_WIDTH]) ?
                        (a[`PRD_WIDTH-1:0] > b[`PRD_WIDTH-1:0]) :
                        (a[`PRD_WIDTH-1:0] < b[`PRD_WIDTH-1:0]));
    end
endfunction

function fifoid_lt;
    input [`PRD_WIDTH:0] a;
    input [`PRD_WIDTH:0] b;
    begin
        fifoid_lt = ((a[`PRD_WIDTH] == b[`PRD_WIDTH]) ?
                        (a[`PRD_WIDTH-1:0] < b[`PRD_WIDTH-1:0]) :
                        (a[`PRD_WIDTH-1:0] > b[`PRD_WIDTH-1:0]));
    end
endfunction
