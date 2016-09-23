%% -------------------------------------------------------------------
%%
%% basho_bench: Benchmarking Suite
%%
%% Copyright (c) 2009-2010 Basho Techonologies
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
-module(basho_bench_driver_tpcc).

-export([new/1,
	    read/5,
         run/4]).

-include("basho_bench.hrl").
-include("tpcc.hrl").

-define(TIMEOUT, 15000).
-define(READ_TIMEOUT, 15000).

-record(state, {worker_id,
                time,
                part_list,
                expand_part_list,
                hash_length,
                w_per_dc,
                c_c_last,
                c_c_id,
                c_ol_i_id,
                %my_table,
                hash_dict,
                other_master_ids,
                dc_rep_ids,
                no_rep_ids,
                item_ranges,
                num_nodes,
                access_master,
                access_slave,
                payment_master,
                payment_slave,
                new_order_committed,
                node_id,
                specula,
                tx_server,
                target_node}).

%% ====================================================================
%% API
%% ====================================================================

new(Id) ->
    %% Make sure bitcask is available
    case code:which(antidote) of
        non_existing ->
            ?FAIL_MSG("~s requires antidote to be available on code path.\n",
                      [?MODULE]);
        _ ->
            ok
    end,

    random:seed(os:timestamp()),
    %_PbPorts = basho_bench_config:get(antidote_pb_port),
    MyNode = basho_bench_config:get(antidote_mynode),
    Cookie = basho_bench_config:get(antidote_cookie),
    IPs = basho_bench_config:get(antidote_pb_ips),
    MasterToSleep = basho_bench_config:get(master_to_sleep),
    Specula = basho_bench_config:get(specula),
    Concurrent = basho_bench_config:get(concurrent),
   
    AccessMaster = basho_bench_config:get(access_master),
    AccessSlave = basho_bench_config:get(access_slave),
    PaymentMaster = math:pow(AccessMaster/100, 10)*100, %basho_bench_config:get(payment_master),
    PaymentSlave = 100 - PaymentMaster, %basho_bench_config:get(payment_slave),
    WPerNode = basho_bench_config:get(w_per_dc),

    TargetNode = lists:nth(((Id-1) rem length(IPs)+1), IPs),
    case Id of 1 ->
    	case net_kernel:start(MyNode) of
        	{ok, _} -> true = erlang:set_cookie(node(), Cookie),  %?INFO("Net kernel started as ~p\n", [node()]);
    			   _Result = net_adm:ping(TargetNode),
    			   HashFun =  rpc:call(TargetNode, hash_fun, get_hash_fun, []), 
			        ets:insert(meta_info, {hash_fun, HashFun});
        	{error, {already_started, _}} ->
            		?INFO("Net kernel already started as ~p\n", [node()]),  ok;
        	{error, Reason} ->
            	?FAIL_MSG("Failed to start net_kernel for ~p: ~p\n", [?MODULE, Reason])
    	end;
	     _ -> ok
    end,

    %% Choose the node using our ID as a modulus
    [{hash_fun, {PartList, ReplList, NumDcs}}] = ets:lookup(meta_info, hash_fun), 

    %?INFO("Using target node ~p for worker ~p\n", [TargetNode, Id]),

    %% PartList is in the form of [{N, [{Part1, Node}, {Part2, Node}]}, {}]....

    %lager:info("My Rep Ids is ~p, my rep list is ~p", [MyRepIds, MyRepList]),
    AllNodes = [N || {N, _} <- PartList],
    NodeId = index(TargetNode, AllNodes),
    NumNodes = length(AllNodes),

    MyTxServer = 
            case length(IPs) of 1 ->
                    case Id of 1 -> 
                                NameLists = lists:foldl(fun(WorkerId, Acc) -> [WorkerId|Acc]
                                                    end, [], lists:seq(1, Concurrent)),
                                Pids = locality_fun:get_pids(TargetNode, lists:reverse(NameLists)), 
                                lists:foldl(fun(P, Acc) -> ets:insert(meta_info, {Acc, P}), Acc+1 end, 1, Pids),
                                hd(Pids);
                            _ ->  [{Id, Pid}] = ets:lookup(meta_info, Id),
                          Pid
                    end;
                            _ ->
                            case Id of 1 -> timer:sleep(MasterToSleep);
                                   _ -> ok
                            end, 
                            locality_fun:get_pid(TargetNode, Id)
    end,
    %case Id of 1 -> timer:sleep(MasterToSleep);
   % 	       _ -> timer:sleep(ToSleep)
   % end,
    %MyTxServer = locality_fun:get_pid(TargetNode, list_to_atom(atom_to_list(TargetNode) 
    %        ++ "-cert-" ++ integer_to_list((Id-1) div length(IPs)+1))),

    {OtherMasterIds, DcRepIds, DcNoRepIds, HashDict} = locality_fun:get_locality_list(PartList, ReplList, NumDcs, TargetNode, single_dc_read),
    HashDict1 = locality_fun:replace_name_by_pid(TargetNode, dict:store(cache, TargetNode, HashDict)),
    %lager:info("OtherMasterId is ~w, DcRep Id is ~w", [OtherMasterIds, DcRepIds]),

    ExpandPartList = lists:flatten([L || {_, L} <- PartList]),
    %lager:info("Ex list is ~w", [ExpandPartList]),
    HashLength = length(ExpandPartList),

    %lager:info("Part list is ~w, hash dict is ~w",[PartList, dict:to_list(HashDict)]),
    %MyTable =ets:new(my_table, [private, set]),
    %Key1 = "C_C_LAST",
    %Key2 = "C_C_ID",
    %Key3 = "C_OL_I_ID",
    %Part1 = get_partition(Key1, ExpandPartList, HashLength),
    %Part2 = get_partition(Key2, ExpandPartList, HashLength),
    %Part3 = get_partition(Key3, ExpandPartList, HashLength),
    %{ok, C_C_LAST} = rpc:call(TargetNode, tx_cert_sup, single_read, [MyTxServer, Key1, Part1]),
    %{ok, C_C_ID} = rpc:call(TargetNode, tx_cert_sup, single_read, [MyTxServer, Key2, Part2]),
    %{ok, C_OL_I_ID} = rpc:call(TargetNode, tx_cert_sup, single_read, [MyTxServer, Key3, Part3]),
    C_C_LAST=54, C_C_ID=68, C_OL_I_ID=1544,
    ItemRanges = init_item_ranges(NumNodes, ?NB_MAX_ITEM),
    %lager:info("Cclast ~w, ccid ~w, coliid ~w, item ranges are ~p", [C_C_LAST, C_C_ID, C_OL_I_ID, ItemRanges]),
    {ok, #state{time={1,1,1}, worker_id=Id,
               tx_server=MyTxServer,
               access_master=AccessMaster,
               access_slave=AccessSlave,
               payment_master=PaymentMaster,
               payment_slave=PaymentSlave,
               part_list = PartList,
               hash_dict = HashDict1,
               w_per_dc=WPerNode,
               %my_table=MyTable,
               other_master_ids = OtherMasterIds,
               dc_rep_ids = DcRepIds,
               no_rep_ids = DcNoRepIds,
               %no_rep_list = SlaveRepList,
               item_ranges = ItemRanges,
               expand_part_list = ExpandPartList,
               hash_length = HashLength,   
               specula = Specula,
               c_c_last = C_C_LAST,
               c_c_id = C_C_ID,
               c_ol_i_id = C_OL_I_ID, 
               num_nodes = NumNodes,
               node_id = NodeId,
               target_node=TargetNode}}.

%% @doc Warehouse, District are always local.. Only choose to access local or remote objects when reading
%% objects. 
run(new_order, TxnSeq, MsgId, State=#state{part_list=PartList, tx_server=TxServer, 
        other_master_ids=OtherMasterIds, dc_rep_ids=DcRepIds, hash_dict=HashDict, no_rep_ids=_SlaveRepIds, node_id=DcId, 
        worker_id=WorkerId, w_per_dc=WPerNode, item_ranges=ItemRanges, c_c_id=C_C_ID, c_ol_i_id=C_OL_I_ID, 
        access_master=AccessMaster, access_slave=AccessSlave}) ->
    RS = dict:new(),
    WS = dict:new(),
    %LocalWS = dict:new(),
    %RemoteWS = dict:new(),

	%% TODO: maybe need to change warehouse
    WarehouseId = WPerNode * (DcId-1) + WorkerId rem WPerNode + 1,
    %lager:info("MyDc is ~w, warehouse is ~w", [DcId, WarehouseId]),
    DistrictId = tpcc_tool:random_num(1, ?NB_MAX_DISTRICT),
    CustomerId = tpcc_tool:non_uniform_random(C_C_ID, ?A_C_ID, 1, ?NB_MAX_CUSTOMER),
    NumItems = tpcc_tool:random_num(?MIN_ITEM, ?MAX_ITEM),
    %lager:info("DistrictId is ~w, Customer Id is ~w, NumItems is ~w", [DistrictId, CustomerId, NumItems]),

    %TxId = {tx_id, tpcc_tool:now_nsec(), self()}, %,gen_server:call({global, TxServer}, {start_tx}),
    TxId = gen_server:call(TxServer, {start_tx, TxnSeq}),
    %lager:info("TxId is ~w", [TxId]),
    CustomerKey = tpcc_tool:get_key_by_param({WarehouseId, DistrictId, CustomerId}, customer), 
    _Customer = read_from_node(TxServer, TxId, CustomerKey, to_dc(WarehouseId, WPerNode), DcId, PartList, HashDict), 
    WarehouseKey = tpcc_tool:get_key_by_param({WarehouseId}, warehouse),

    _Warehouse = read_from_node(TxServer, TxId, WarehouseKey, to_dc(WarehouseId, WPerNode), DcId, PartList, HashDict),

    DistrictKey = tpcc_tool:get_key_by_param({WarehouseId, DistrictId}, district),
    District = read_from_node(TxServer, TxId, DistrictKey, to_dc(WarehouseId, WPerNode), DcId, PartList, HashDict),
    OId = District#district.d_next_o_id,

    NewOrder = tpcc_tool:create_neworder(WarehouseId, DistrictId, OId),
    NewOrderKey = tpcc_tool:get_key_by_param({WarehouseId, DistrictId, OId}, neworder),
    WS1 = dict:store({WarehouseId, NewOrderKey}, NewOrder, WS), 
    %LocalWS1 = add_to_writeset(NewOrderKey, NewOrder, lists:nth(DcId, PartList), LocalWS),
    District1 = District#district{d_next_o_id=(OId+1) rem ?MAX_NEW_ORDER},
    %LocalWS2 = add_to_writeset(DistrictKey, District1, lists:nth(DcId, PartList), LocalWS1),
    WS2 = dict:store({WarehouseId, DistrictKey}, District1, WS1), 

    Seq = lists:seq(1, NumItems),
    {WS3, _, AllLocal} = lists:foldl(fun(OlNumber, {TWS, TRS, AL}) ->
                    case TWS of error -> {error, error, error};
                                _ ->
                    WId = pick_warehouse(DcId, OtherMasterIds, DcRepIds, WPerNode, AccessMaster, AccessSlave),
                    {Min, Max} = lists:nth(to_dc(WId, WPerNode), ItemRanges),
                    %ItemId = case tpcc_tool:random_num(1, 100) of
                    %            1 ->
                    %                -12345;
                    %            _ ->
                    %lager:info("C_OL_I_ID is ~w, Min is  ~w", [C_OL_I_ID, Min]),
                    ItemId = tpcc_tool:non_uniform_random(C_OL_I_ID, ?A_OL_I_ID, Min, Max),
                             %end,
                    Quantity = tpcc_tool:random_num(1, ?NB_MAX_DISTRICT),
                    ItemKey = tpcc_tool:get_key_by_param({ItemId}, item),
                    %Item = read_from_node(TxServer, TxId, ItemKey, WId, PartList, MyRepList),
                    {Item, TRS1} = read_from_cache_or_node(TRS, TxServer, TxId, ItemKey, to_dc(WId, WPerNode), DcId, PartList, HashDict),
                    StockKey = tpcc_tool:get_key_by_param({WId, ItemId}, stock),
                    %Stock = read_from_node(TxServer, TxId, StockKey, WId, PartList, MyRepList),
                    {Stock, TRS2} = read_from_cache_or_node(TRS1, TxServer, TxId, StockKey, to_dc(WId, WPerNode), DcId, PartList, HashDict),
                    case Stock of error ->
                        {error, error, error};
                                    _ ->
                    NewSQuantity = case Stock#stock.s_quantity - Quantity >= 10 of
                                        true -> Stock#stock.s_quantity - Quantity;
                                        false -> Stock#stock.s_quantity - Quantity + 91
                                    end,
                    SRemote = case WId of 
                                    WarehouseId -> Stock#stock.s_remote_cnt;
                                    _ -> Stock#stock.s_remote_cnt+1
                                end,
                    SYtd = Stock#stock.s_ytd,
                    SOrderCnt = Stock#stock.s_order_cnt,
                    Stock1 = Stock#stock{s_quantity=NewSQuantity, s_ytd=SYtd+Quantity, s_remote_cnt=SRemote,
                                   s_order_cnt=SOrderCnt+1},                    
                    {TWS3, TRS3} = add_to_wr_set(WId, StockKey, Stock1, TWS, TRS2),
                    %{LWS1, RWS1} = case WId of
                    %                    DcId -> {add_to_writeset(StockKey, Stock1, lists:nth(DcId, PartList), LWS), RWS};
                    %                    _ -> {LWS, add_to_writeset(StockKey, Stock1, lists:nth(WId, PartList), RWS)}
                    %                end,
                    OlAmount = Quantity * Item#item.i_price,
                    %IData = Item#item.i_data,
                    %SData = Stock#stock.s_data,;
                    OlDistInfo = get_district_info(Stock1, DistrictId),
                    Orderline = tpcc_tool:create_orderline(WarehouseId, DistrictId, WId, OId, ItemId, 
                        OlNumber, Quantity, OlAmount, OlDistInfo),
                    %LWS2 = add_to_writeset(tpcc_tool:get_key(Orderline), Orderline, lists:nth(DcId, PartList), LWS1),
                    TWS4 = dict:store({WarehouseId, tpcc_tool:get_key(Orderline)}, Orderline, TWS3),
                    AL1 = case WId of 
                                    WarehouseId -> AL;
                                    _ -> 0 
                                end,
                    {TWS4, TRS3, AL1}
                    end end
            end, {WS2, RS, 1}, Seq),

    case WS3 of error -> {aborted, {[], [], []}, State};
                _ ->
    Order = tpcc_tool:create_order(WarehouseId, DistrictId, OId, NumItems, CustomerId, tpcc_tool:now_nsec(), AllLocal), 
    OrderKey = tpcc_tool:get_key_by_param({WarehouseId, DistrictId, OId}, order),
    WS4 = dict:store({WarehouseId, OrderKey}, Order, WS3),
    %LocalWS4 = add_to_writeset(OrderKey, Order, lists:nth(DcId, PartList), LocalWS3),
    {LocalWriteList, RemoteWriteList} = get_local_remote_writeset(WS4, PartList, DcId, WPerNode),
    %lager:info("Local Write set is ~p", [LocalWriteList]),
    %lager:info("Remote Write set is ~p", [RemoteWriteList]),
    %DepsList = ets:lookup(dep_table, TxId),
    %% ************ read time *****************
    %% ************ read time *****************
    Response = gen_server:call(TxServer, {certify_update, TxId, LocalWriteList, RemoteWriteList, MsgId}, ?TIMEOUT),%, length(DepsList)}),
    case Response of
        {ok, {committed, _CommitTime, Info}} ->
            {ok, Info, State};
        {ok, {specula_commit, _SpeculaCT, Info}} ->
            {specula_commit, Info, State};
        {cascade_abort, Info} ->
            {cascade_abort, Info, State};
        {error,timeout} ->
            lager:info("Timeout on client ~p",[TxServer]),
            {error, timeout, State};
        {aborted, Info} ->
            {aborted, Info, State};
        {badrpc, Reason} ->
            {error, Reason, State}
    end
    end;

%% @doc Payment transaction of TPC-C
run(payment, TxnSeq, MsgId, State=#state{part_list=PartList, tx_server=TxServer, worker_id=WorkerId,
        hash_dict=HashDict, dc_rep_ids=DcRepIds, other_master_ids=OtherMasterIds, w_per_dc=WPerNode, 
        node_id=DcId, payment_master=PaymentMaster, payment_slave=PaymentSlave, 
        c_c_id=C_C_ID, c_c_last = C_C_LAST}) ->


    WS = dict:new(),
    %LocalWS = dict:new(),
    %RemoteWS = dict:new(),
    TWarehouseId = WPerNode * (DcId-1) + WorkerId rem WPerNode +1, 
	DistrictId = tpcc_tool:random_num(1, ?NB_MAX_DISTRICT),
	
    %% TODO: this should be changed. 
    %{CWId, CDId} = case tpcc_tool:random_num(1, 100) =< AccessMaster of
	%			        true ->
	%			            {TWarehouseId, DistrictId};
	%			        false ->
	%						RId = tpcc_tool:random_num(1, ?NB_MAX_DISTRICT),
	%			    		N = tpcc_tool:random_num(1, NumDcs-1),
	%						case N >= TWarehouseId of
	%							true -> {N+1, RId};  false -> {N, RId}
	%						end
	%			  	end,
    CWId = pick_warehouse(DcId, OtherMasterIds, DcRepIds, WPerNode, PaymentMaster, PaymentSlave),
    CDId = DistrictId,
	PaymentAmount = tpcc_tool:random_num(100, 500000) / 100.0,

    %% Only customer can be remote, everything else(Warehouse, District) should be local
	%TxId = {tx_id, tpcc_tool:now_nsec(), self()},	

    TxId = gen_server:call(TxServer, {start_tx, TxnSeq}),
    %lager:warning("TxId is ~w", [TxId]),
	WarehouseKey = tpcc_tool:get_key_by_param({TWarehouseId}, warehouse),
    Warehouse = read_from_node(TxServer, TxId, WarehouseKey, to_dc(TWarehouseId, WPerNode), DcId, PartList, HashDict),
	WYtdKey = WarehouseKey++":w_ytd",
	WYtd = read_from_node(TxServer, TxId, WYtdKey, to_dc(TWarehouseId, WPerNode), DcId, PartList, HashDict),
    case is_number(WYtd) of true -> ok;  false -> lager:warning("TxId is ~w, WTyd is ~w", [TxId, WYtd]), WYtd=haah end,
	WYtd1 = WYtd+ PaymentAmount,
	WS1 = dict:store({TWarehouseId, WYtdKey}, WYtd1, WS),
	DistrictKey = tpcc_tool:get_key_by_param({TWarehouseId, DistrictId}, district),
    District = read_from_node(TxServer, TxId, DistrictKey, to_dc(TWarehouseId, WPerNode), DcId, PartList, HashDict),
	DYtdKey = DistrictKey++":d_ytd",
	DYtd = read_from_node(TxServer, TxId, DYtdKey, to_dc(TWarehouseId, WPerNode), DcId, PartList, HashDict),
    case is_number(DYtd) of true -> ok;  false -> lager:warning("TxId is ~w, DTyd is ~w", [TxId, DYtd]), DYtd=haah end,
	DYtd1 = DYtd+ PaymentAmount,
	WS2 = dict:store({TWarehouseId, DYtdKey}, DYtd1, WS1),
	
		%% 60% change to load customer by name, otherwise not by name
    CW = case tpcc_tool:random_num(1, 100) =< 60 of
			true ->
				Rand = trunc(tpcc_tool:non_uniform_random(C_C_LAST, ?A_C_LAST, 0, ?MAX_C_LAST)),
	         	CLastName = tpcc_tool:last_name(Rand),
				CustomerLookupKey = tpcc_tool:get_key_by_param({CWId, CDId, CLastName}, customer_lookup),
				CustomerLookup = read_from_node(TxServer, TxId, CustomerLookupKey, to_dc(CWId, WPerNode), DcId, PartList, HashDict),
                Ids = CustomerLookup#customer_lookup.ids,
                Customers= lists:foldl(fun(Id, Acc) ->
                            CKey = tpcc_tool:get_key_by_param({CWId, CDId, Id}, customer),
                            C = read_from_node(TxServer, TxId, CKey, to_dc(CWId, WPerNode), DcId, PartList, HashDict),
                            case C of
                                error -> Acc;  _ -> [C|Acc]
                            end end, [], Ids),
                SortedCustomers = lists:sort(Customers),
                Middle = (length(Customers) + 1) div 2,
                lists:nth(Middle, SortedCustomers);
	       	false ->
	         	CustomerID = tpcc_tool:non_uniform_random(C_C_ID, ?A_C_ID, 1, ?NB_MAX_CUSTOMER),
				CKey = tpcc_tool:get_key_by_param({CWId, CDId, CustomerID}, customer),
				read_from_node(TxServer, TxId, CKey, to_dc(CWId, WPerNode), DcId, PartList, HashDict)
		end,
    CWBalanceKey = tpcc_tool:get_key(CW)++":c_balance",
    CWBalance = read_from_node(TxServer, TxId, CWBalanceKey, to_dc(CWId, WPerNode), DcId, PartList, HashDict),
    CWBalance1 = CWBalance + PaymentAmount,
    WS3 = dict:store({CWId, CWBalanceKey}, CWBalance1, WS2),
    WName = Warehouse#warehouse.w_name,
    DName = District#district.d_name,
    HData = lists:sublist(WName, 1, 10) ++ "  " ++ lists:sublist(DName, 1, 10),
    %% History should be local
    History = tpcc_tool:create_history(TWarehouseId, DistrictId, CWId, CDId, 
                                       CW#customer.c_id, tpcc_tool:now_nsec(), PaymentAmount, HData),
    HistoryKey = tpcc_tool:get_key(History),
    WS4 = dict:store({TWarehouseId, HistoryKey}, History, WS3),
    {LocalWriteList, RemoteWriteList} = get_local_remote_writeset(WS4, PartList, DcId, WPerNode),
    %DepsList = ets:lookup(dep_table, TxId),
    Response =  gen_server:call(TxServer, {certify_update, TxId, LocalWriteList, RemoteWriteList, MsgId}, ?TIMEOUT),%, length(DepsList)}),
    case Response of
        {ok, {committed, _CommitTime, Info}} ->
            {ok, Info, State};
        {ok, {specula_commit, _SpeculaCT, Info}} ->
            {specula_commit, Info, State};
        {cascade_abort, Info} ->
            {cascade_abort, Info, State};
        {error,timeout} ->
            lager:info("Timeout on client ~p",[TxServer]),
            {error, timeout, State};
        {aborted, Info} ->
            {aborted, Info, State};
        {badrpc, Reason} ->
            {error, Reason, State}
    end;

%% @doc Payment transaction of TPC-C
run(order_status, TxnSeq, MsgId, State=#state{part_list=PartList, tx_server=TxServer,
        hash_dict=HashDict, node_id=DcId, w_per_dc=WPerNode, worker_id=WorkerId, 
        c_c_id=C_C_ID, c_c_last = C_C_LAST, specula=Specula}) ->
    TWarehouseId = WPerNode * (DcId-1) + WorkerId rem WPerNode +1, 
	DistrictId = tpcc_tool:random_num(1, ?NB_MAX_DISTRICT),
	
	%TxId = {tx_id, tpcc_tool:now_nsec(), self()},
    TxId = gen_server:call(TxServer, {start_tx, TxnSeq}),
	CW = case tpcc_tool:random_num(1, 100) =< 60 of
			true ->
				Rand = trunc(tpcc_tool:non_uniform_random(C_C_LAST, ?A_C_LAST, 0, ?MAX_C_LAST)),
	         	CLastName = tpcc_tool:last_name(Rand),
				CustomerLookupKey = tpcc_tool:get_key_by_param({TWarehouseId, DistrictId, CLastName}, customer_lookup),
				CustomerLookup = read_from_node(TxServer, TxId, CustomerLookupKey, to_dc(TWarehouseId, WPerNode), DcId, PartList, HashDict),
                case CustomerLookup of
                    error ->
                        lager:error("Key not found by last name ~p", [CLastName]),
                        error;
                    _ ->
                        Ids = CustomerLookup#customer_lookup.ids,
                        Customers= lists:foldl(fun(Id, Acc) ->
                                    CKey = tpcc_tool:get_key_by_param({TWarehouseId, DistrictId, Id}, customer),
                                    C = read_from_node(TxServer, TxId, CKey, to_dc(TWarehouseId, WPerNode), DcId, PartList, HashDict),
                                    case C of
                                        error -> Acc;  _ -> [C|Acc]
                                    end end, [], Ids),
                        SortedCustomers = lists:sort(Customers),
                        Middle = (length(Customers) + 1) div 2,
                        %lager:info("Loading by Id... Got ~w keys", [length(Customers)]),
                        lists:nth(Middle, SortedCustomers)
                end;
	       	false ->
	         	CustomerID = tpcc_tool:non_uniform_random(C_C_ID, ?A_C_ID, 1, ?NB_MAX_CUSTOMER),
				CKey = tpcc_tool:get_key_by_param({TWarehouseId, DistrictId, CustomerID}, customer),
				read_from_node(TxServer, TxId, CKey, to_dc(TWarehouseId, WPerNode), DcId, PartList, HashDict)
		end,
    CWLastOrder = CW#customer.c_last_order,
    OrdKey = tpcc_tool:get_key_by_param({TWarehouseId, DistrictId, CWLastOrder}, order),
    LastOne = read_from_node(TxServer, TxId, OrdKey, to_dc(TWarehouseId, WPerNode), DcId, PartList, HashDict),
    %lager:info("CWId is ~w, length of orderlist is ~w", [CWId, length(OrderList)]),
    NumLines = LastOne#order.o_ol_cnt,
    Seq2 = lists:seq(1, NumLines),
    %lager:info("Loading ~w orderlines", [NumLines]),
    OWId = LastOne#order.o_w_id,
    ODId = LastOne#order.o_d_id,
    OId = LastOne#order.o_id,
    lists:foreach(fun(Number) ->
            OlKey = tpcc_tool:get_key_by_param({OWId, ODId, OId, Number}, orderline),
            _Ol = read_from_node(TxServer, TxId, OlKey, to_dc(TWarehouseId, WPerNode), DcId, PartList, HashDict)
            end, Seq2),
    case Specula of 
        true ->
            Response =  gen_server:call(TxServer, {certify_read, TxId, MsgId}, ?TIMEOUT),
            case Response of
                {ok, {committed, _CommitTime, Info}} ->
                    {ok, Info, State};
                {ok, {specula_commit, _SpeculaCT, Info}} ->
                    {specula_commit, Info, State};
                {cascade_abort, Info} ->
                    {cascade_abort, Info, State};
                {error,timeout} ->
                    lager:info("Timeout on client ~p",[TxServer]),
                    {error, timeout, State};
                {aborted, Info} ->
                    {aborted, Info, State};
                {badrpc, Reason} ->
                    {error, Reason, State}
            end;
        _ ->
            {ok, State}
    end.

get_partition(Key, PartList, HashLength) ->
    Num = crypto:bytes_to_integer(erlang:md5(Key)) rem HashLength +1,
    lists:nth(Num, PartList).
    
index(Elem, L) ->
    index(Elem, L, 1).

index(_, [], _) ->
    -1;
index(E, [E|_], N) ->
    N;
index(E, [_|L], N) ->
    index(E, L, N+1).

read_from_node(TxServer, TxId, Key, DcId, MyDcId, PartList, HashDict) ->
    {ok, V} = case DcId of
        MyDcId ->
            {_, L} = lists:nth(DcId, PartList),
            Index = crypto:bytes_to_integer(erlang:md5(Key)) rem length(L) + 1,
            Part = lists:nth(Index, L),
            gen_server:call(TxServer, {read, Key, TxId, Part}, ?READ_TIMEOUT);
        _ ->
            case dict:find(DcId, HashDict) of
                error ->
                    {_, L} = lists:nth(DcId, PartList),
                    Index = crypto:bytes_to_integer(erlang:md5(Key)) rem length(L) + 1,
                    Part = lists:nth(Index, L),
                    CacheServName = dict:fetch(cache, HashDict), 
                    gen_server:call(CacheServName, {read, Key, TxId, Part}, ?READ_TIMEOUT);
                {ok, N} ->
                    {_, L} = lists:nth(DcId, PartList),
                    Index = crypto:bytes_to_integer(erlang:md5(Key)) rem length(L) + 1,
                    Part = lists:nth(Index, L),
                    gen_server:call(N, {read, Key, TxId, Part}, ?READ_TIMEOUT)
            end
    end,
    case V of
        [] ->
            lager:error("Key ~p not found!!!! Should read from dc ~w, my dc is ~w,~w", [Key, DcId, MyDcId, node()]),
            error;
        _ ->
            V
    end.
    %case Res of
    %    {specula, DepTx} ->
    %        ets:insert(dep_table, {TxId, DepTx});
    %    ok ->
    %        ok
    %end,

read_from_cache_or_node(ReadSet, TxServer, TxId, Key, DcId, MyDcId, PartList, HashDict) ->
    case dict:find(Key, ReadSet) of
        {ok, V} ->
            %lager:info("In read set..Key ~p, V ~p, Readset ~p", [Key, V, ReadSet]),
            {V, ReadSet};
        error ->
            V = read_from_node(TxServer, TxId, Key, DcId, MyDcId, PartList, HashDict),
            ReadSet1 = dict:store(Key, V, ReadSet),
            %lager:info("Not in read set..Key ~p, V ~p, Readset ~p", [Key, V, ReadSet1]),
            {V, ReadSet1}
    end.
 
read(TxServer, TxId, Key, ExpandPartList, HashLength) ->
    Part = get_partition(Key, ExpandPartList, HashLength),
    {ok, V} = gen_server:call(TxServer, {read, Key, TxId, Part}, ?READ_TIMEOUT),
    case V of
        [] ->
            lager:error("Key ~p not found!!!!", [Key]),
            error;
        _ ->
            %lager:info("Reading ~p, ~p", [Key, V]),
            V
    end.

get_local_remote_writeset(WriteSet, PartList, LocalDcId, WPerNode) ->
    {LWSD, RWSD} = dict:fold(fun({WId, Key}, Value, {LWS, RWS}) ->
                    Id = (WId-1) div WPerNode + 1, 
                    case Id of LocalDcId -> {add_to_writeset(Key, Value, lists:nth(LocalDcId, PartList), LWS), RWS};
                               _ -> {LWS, add_to_writeset(Key, Value, lists:nth(Id, PartList), RWS)}
                    end end, {dict:new(), dict:new()}, WriteSet),
    %L = dict:fetch_keys(RWSD),
    %NodeSet = lists:foldl(fun({_, N}, S) -> sets:add_element(N, S) end, sets:new(), L),
    %ets:update_counter(MyTable, TxType, [{2, 1}, {3, length(L)}, {4,sets:size(NodeSet)}]),
    {dict:to_list(LWSD), dict:to_list(RWSD)}.

add_to_wr_set(DcId, Key, Value, WriteSet, ReadSet) ->
    WriteSet1 = dict:store({DcId, Key}, Value, WriteSet),
    ReadSet1 = dict:store(Key, Value, ReadSet),
    {WriteSet1, ReadSet1}.    

add_to_writeset(Key, Value, {_, PartList}, WSet) ->
    Index = crypto:bytes_to_integer(erlang:md5(Key)) rem length(PartList) + 1,
    Part = lists:nth(Index, PartList),
    %lager:info("Adding  ~p, ~p to ~w", [Key, Value, Part]),
    dict:append(Part, {Key, Value}, WSet).

pick_warehouse(MyId, RepIds, SlaveRepIds, WPerNode, AccessMaster, AccessRep) ->
    %lager:info("~w ~w ~w ~w ~w ~w", [MyId, RepIds, SlaveRepIds, WPerNode, AccessMaster, AccessRep]),
    R = random:uniform(100),
    case R =< AccessMaster of
        true ->
            WPerNode*(MyId-1) + R rem WPerNode +1;
        false ->
            case R =< AccessMaster + AccessRep of
                true ->
                    L = length(RepIds),
                    case L of 0 ->
                                N = R rem (length(SlaveRepIds) * WPerNode) + 1,
                                F = (N-1) div WPerNode +1,
                                S = N rem WPerNode,
                                WPerNode*(lists:nth(F, SlaveRepIds)-1)+S+1;
                            _ ->
                                N = R rem (L * WPerNode),
                                F = N div WPerNode +1, 
                                S = N rem WPerNode,
                                WPerNode*(lists:nth(F, RepIds)-1)+S+1
                    end;
                false ->
                    L = length(SlaveRepIds),
                    case L of 0 ->
                                N = R rem (length(RepIds) * WPerNode),
                                F = N div WPerNode +1,    
                                S = N rem WPerNode,
                                WPerNode*(lists:nth(F, RepIds)-1)+S+1;
                            _ ->
                                N = R rem (L * WPerNode) + 1,
                                F = (N-1) div WPerNode +1, 
                                S = N rem WPerNode,
                                WPerNode*(lists:nth(F, SlaveRepIds)-1)+S+1
                    end
            end
    end.

init_item_ranges(NumDCs, Max) ->
    Remainder = Max rem NumDCs,
    DivItems = (Max-Remainder)/NumDCs,
    Seq = lists:seq(1, NumDCs),
    lists:foldl(fun(N, Acc) ->
                    FirstItem = ((N-1) * DivItems) + 1,
                    LastItem = case N of
                                    NumDCs ->
                                        DivItems + Remainder + FirstItem - 1;
                                    _ ->
                                        DivItems + FirstItem -1
                                end,
                    Acc++[{trunc(FirstItem), trunc(LastItem)}] 
                    end, [], Seq).
    
get_district_info(Stock, 1) ->
    Stock#stock.s_dist_01;
get_district_info(Stock, 2) ->
    Stock#stock.s_dist_02;
get_district_info(Stock, 3) ->
    Stock#stock.s_dist_03;
get_district_info(Stock, 4) ->
    Stock#stock.s_dist_04;
get_district_info(Stock, 5) ->
    Stock#stock.s_dist_05;
get_district_info(Stock, 6) ->
    Stock#stock.s_dist_06;
get_district_info(Stock, 7) ->
    Stock#stock.s_dist_07;
get_district_info(Stock, 8) ->
    Stock#stock.s_dist_08;
get_district_info(Stock, 9) ->
    Stock#stock.s_dist_09;
get_district_info(Stock, 10) ->
    Stock#stock.s_dist_10.

%get_replica(_, []) ->
%    false;
%get_replica(E, [{E, N}|_]) ->
%    N;
%get_replica(E, [_|L]) ->
%    get_replica(E, L).

to_dc(WId, WPerNode) ->
    (WId-1) div WPerNode + 1.

