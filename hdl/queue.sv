/****************************************************************
 * queue.sv - queue structure for storing memory requests
 *
 * Authors       : Viraj Khatri (vk5@pdx.edu)
 *               : Varden Prabahr (nagavar2@pdx.edu)
 *               : Sai Krishnan (saikris2@pdx.edu)
 *               : Chirag Chaudhari (chirpdx@pdx.edu)
 * Last Modified : 16 November, 2021
 *
 * Description   :
 * -----------
 * takes input from parser, and stores in queue
 ****************************************************************/

import global_defs::*;

module queue
(
	// inputs
	input  logic               clk, rst_n,

	// inputs from parser
	input  parser_out_struct_t in,                    // has op_ready_s, opcode, address and time_cpu

	// outputs to parser
	output logic               pending_request,       // flag - request is not acknowledged yet
	output logic               queue_full,            // flag - queue is full

	// outputs
	output parser_out_struct_t out,                   // output to next module (memory controller / DRAM?)
	output parser_out_struct_t queue[$:QUEUE_SIZE-1], // queue to store many memory requests
	output age_counter_t       age[$:QUEUE_SIZE-1],
	output int_t               queue_time             // display what time is queue currently at (int)
);


int_t curr_time;
assign queue_time = curr_time;

logic half_clk, out_ready;
parser_out_struct_t out_buffer;

/***************************
 * flags to send to parser *
 ***************************/
always_comb begin : queue_flag
	if (queue.size() == QUEUE_SIZE) queue_full = 1'b1;
	else queue_full = 1'b0;
end : queue_flag

/*************************
 * print on queue output *
 *************************/
function automatic queue_output_display(parser_out_struct_t out);
	$display("%t : OUTPUT DRAM : element:'{time_cpu:%0t, opcode:%p, address:0x%h}' : curr_time=%0d",
				 $time,
				 out.time_cpu,
				 out.opcode,
				 out.address,
				 curr_time);

	// determining bank group, bank, column, row
	$display("%t :             : bank group=%0d, bank=%0d, column=%0d, row=%0d",
	          $time,
	          ((bank_group_mask & out.address) >> BG_OFFSET),
	          ((bank_mask       & out.address) >> BANK_OFFSET),
	          ((column_mask     & out.address) >> COLUMN_OFFSET),
	          ((row_mask        & out.address) >> ROW_OFFSET));

endfunction

/******************
 * dataflow block *
 ******************/
always_ff@(posedge clk or negedge rst_n) begin : parser_in
	if ($test$plusargs("per_clock"))
		$display("%t :    START    : full,pend=%b,%b  curr_time=%0d : in=%p", $time, queue_full, pending_request, curr_time, in);

	if (!rst_n) begin
		queue.delete();
		curr_time <= 0;
		pending_request <= 1'b0;
	end

	else begin

		// output from queue
		// TODO : 2-d array to keep track of status of all rows on DRAM
		// use that array to determine ACT/READ/WRITE statuses

		// forcing age pop on 100+ CPU_clock old entries
		if (age[$] >= 100) begin
			out_buffer <= queue[$];
			out_ready <= 1;
		end


		// taking input from parser
		if (in.op_ready_s) begin
			if (queue.size() == 0) begin
				curr_time <= in.time_cpu; // time skip in empty queue
				if ($test$plusargs("debug")) $display("%t : QUEUE_EMPTY : queue is empty, advancting time to %0t",$time,in.time_cpu);
			end

			if ((queue.size() < QUEUE_SIZE && curr_time >= in.time_cpu) || queue.size() == 0) begin
				queue.push_front(in);
				age.push_front(0);
				pending_request <= 1'b0;


				if ($test$plusargs("debug")) begin
					$display("%t :   INSERT    : element:'{time_cpu:%0t, opcode:%p, address:0x%h}' : curr_time=%0d",
					          $time,
					          in.time_cpu,
					          in.opcode,
					          in.address,
					          curr_time);
					$display("%t :             : queue has %0d elements now :   '{",$time, queue.size());
					for (int j=0; j < queue.size(); j++) begin
						$display("#                                                              '{time_cpu:%0t, opcode:%p, address:0x%h}' '{age:%d}',",
						           queue[j].time_cpu,
						           queue[j].opcode,
						           queue[j].address,
						           age[j]);
					end
					$display("#                                                             }'");
				end
			end else begin
				pending_request <= 1'b1;
			end
		end
	end
end : parser_in

/*******************
 * aging all queue *
 *******************/
always_ff@(posedge clk) begin : queue_age
	curr_time++;
	for (int i=0; i<queue.size(); i++) begin
		age[i]++;
	end
end : queue_age

/*************************************************
 * Outputting requests to DRAM on half frequency *
 *************************************************/
always_ff@(posedge clk or negedge rst_n) begin
	if (!rst_n) half_clk = 0;
	else half_clk <= ~half_clk;
end

always_ff@(posedge half_clk) begin
	if (out_ready) begin
		out <= out_buffer;
		out_ready <= 0;

		if ($test$plusargs("debug"))
			queue_output_display(queue[$]); // age popping last element, so display that

		queue.pop_back();
		age.pop_back();

		if ($test$plusargs("debug")) begin
			$display("%t :             : queue has %0d elements now :   '{", $time, queue.size());
			for (int j=0; j < queue.size(); j++) begin
				$display("#                                                              '{time_cpu:%0t, opcode:%p, address:0x%h}' '{age:%d}',",
							  queue[j].time_cpu,
							  queue[j].opcode,
							  queue[j].address,
							  age[j]);
			end
			$display("#                                                             }'");
		end
	end
end

endmodule : queue
