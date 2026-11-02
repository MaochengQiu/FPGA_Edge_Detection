`timescale 1ns/1ps
module tb_direction;
    reg signed [10:0] gx=0,gy=0;wire [1:0] direction;
    img_gradient_direction dut(.gx(gx),.gy(gy),.direction(direction));
    integer f,s,x,y,d,n;
    initial begin
        f=$fopen("direction_vectors.txt","r");if(!f)$fatal(1,"direction vectors");n=0;
        while(!$feof(f))begin
            s=$fscanf(f,"%d %d %d\n",x,y,d);
            if(s==3)begin
                gx=x;gy=y;#1;if(direction!==d[1:0])$fatal(1,"direction gx=%0d gy=%0d got=%0d expected=%0d",x,y,direction,d);
                n=n+1;
            end
        end
        $fclose(f);$display("DIRECTION PASS %0d axes, quadrants, near 22.5/67.5 boundaries, full signed extrema",n);$finish;
    end
endmodule
