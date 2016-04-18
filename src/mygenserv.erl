-include("basho_bench.hrl").
%%%----------------------------------------------------------------------------
%%% @doc An OTP gen_server example
%%% @author Hans Christian v. Stockhausen <hc at vst.io>
%%% @end
%%%----------------------------------------------------------------------------

-module(mygenserv).            %  Nothing new in this section except for the
                               %  next line where we tell the compiler that
-behaviour(gen_server).        %  this module implements the gen_server
                               %  behaviour. The compiler will warn us if
-define(SERVER, ?MODULE).      %  we do not provide all callback functions
                               %  the behaviour announces. It knows what
-record(state, {count}).       %  functions to expect by calling 
                               %  gen_server:behaviour_info(callbacks). Try it.

%%-----------------------------------------------------------------------------
%% API Function Exports
%%-----------------------------------------------------------------------------

-export([                      % Here we define our API functions as before 
  start_link/0,                % - starts and links the process in one step
  stop/0,                      % - stops it
  say_hello/0,                 % - prints "Hello" to stdout
  get_count/0,                 % - returns the count state
  launchWorkersSup/1,
  launchWorkers/0%,
  %set_config/1
  ]).
  
%% ---------------------------------------------------------------------------
%% gen_server Function Exports
%% ---------------------------------------------------------------------------

-export([                      % The behaviour callbacks
  init/1,                      % - initializes our process
  handle_call/3,               % - handles synchronous calls (with response)
  handle_cast/2,               % - handles asynchronous calls  (no response)
  handle_info/2,               % - handles out of band messages (sent with !)
  terminate/2,                 % - is called on shut-down
  code_change/3]).             % - called to handle code changes

%% worker
-record(stateW, { id,
                 keygen,
                 valgen,
                 driver,
                 driver_state,
                 shutdown_on_error,
                 ops,
                 ops_len,
                 rng_seed,
                 parent_pid,
                 worker_pid,
                 sup_id,
                 mode}).

%% driver
-record(stateD, {ips,
                types,
                worker_id,
                time,
                type_dict,
                pb_pid,
                num_partitions,
                set_size,
                commit_time,
                num_reads,
                num_updates,
                pb_port,
                target_node,
                measure_staleness}).

%% sup
-record(stateS, { workers,
                  measurements}).

%% ---------------------------------------------------------------------------
%% API Function Definitions
%% ---------------------------------------------------------------------------

start_link() ->                % start_link spawns and links to a new 
    gen_server:start_link(     %  process in one atomic step. The parameters:
      {global, ?SERVER},        %  - name to register the process under locally
      ?MODULE,                 %  - the module to find the init/1 callback in 
      [],                      %  - what parameters to pass to init/1
      []).                     %  - additional options to start_link

stop() ->                      % Note that we do not use ! anymore. Instead
    gen_server:cast(           %  we use cast to send a message asynch. to
      ?SERVER,                 %  the registered name. It is asynchronous
      stop).                   %  because we do not expect a response.

say_hello() ->                 % Pretty much the same as stop above except
    gen_server:cast(           %  that we send the atom say_hello instead.
      ?SERVER,                 %  Again we do not expect a response but
      say_hello).              %  are only interested in the side effect.

get_count() ->                 % Here, on the other hand, we do expect a 
    gen_server:call(           %  response, which is why we use call to
      ?SERVER,                 %  synchronously invoke our server. The call 
      get_count).              %  blocks until we get the response. Note how
                               %  gen_server:call/2 hides the send/receive
                               %  logic from us. Nice.
                               
launchWorkersSup({SW, SD, SS}) ->
  io:fwrite("hello from mygenserv:launchWorkersSup before\n"),
  gen_server:call(?SERVER, {launchWorkersSup, SW, SD, SS}),
  io:fwrite("hello from mygenserv:launchWorkersSup after\n").
  
launchWorkers() ->
  io:fwrite("hello from mygenserv:launchWorkers before\n"),
  gen_server:call(?SERVER, {launchWorkers}),
  io:fwrite("hello from mygenserv:launchWorkers after\n").    
  
%set_config({SW, SD}) ->              
%  io:fwrite("hello from mygenserv:set_config before\n"),
%  gen_server:call(?SERVER, {set_config, {SW, SD}}),
%  io:fwrite("hello from mygenserv:set_config after\n").
    
                           
%% ---------------------------------------------------------------------------
%% gen_server Function Definitions
%% ---------------------------------------------------------------------------

init([]) ->                    % these are the behaviour callbacks. init/1 is
    {ok, #state{count=0}}.     % called in response to gen_server:start_link/4
                               % and we are expected to initialize state.

%handle_call(get_count, _From, #state{count=Count}) -> 
%    {reply, 
%     Count,                    % here we synchronously respond with Count
%     #state{count=Count+1}     % and also update state
%    }.

handle_call({launchWorkersSup, SW, SD, SS}, _From, #state{count=Count}) -> 
  io:fwrite("hello from mygenserv:handle_call launchWorkersSup 0 \n"),
  basho_bench_sup:start_link({SW, SD, SS}),
  io:fwrite("hello from mygenserv:handle_call launchWorkersSup 1\n"),
    {reply, 
     Count,                    % here we synchronously respond with Count
     #state{count=Count+1}     % and also update state
    }; 
    
handle_call({launchWorkers}, _From, #state{count=Count}) -> 
  io:fwrite("hello from mygenserv:handle_call launchWorkers 0\n"),
  basho_bench_worker:run(basho_bench_sup:workers()),
  io:fwrite("hello from mygenserv:handle_call launchWorkers 1\n"),
    {reply, 
     Count,                    % here we synchronously respond with Count
     #state{count=Count+1}     % and also update state
    }; 
    
handle_call({set_config, {SW, SD}}, _From, #state{count=Count}) -> 
  io:fwrite("hello from mygenserv:handle_call set_config 0\n"),
  %% faire le traitement de set_config sur supervisor et sur worker selon les besoins
  io:fwrite("hello from mygenserv:handle_call set_config 1\n"),
    {reply, 
     Count,                    % here we synchronously respond with Count
     #state{count=Count+1}     % and also update state
    }. 

handle_cast(stop, State) ->    % this is the first handle_case clause that
    {stop,                     % deals with the stop atom. We instruct the
     normal,                   % gen_server to stop normally and return
     State                     % the current State unchanged.
    };                         % Note: the semicolon here....

handle_cast(say_hello, State) -> % ... becuase the second clause is here to
    io:format("Hello~n"),      % handle the say_hello atom by printing "Hello"
    {noreply,                  % again, this is asynch, so noreply and we also
    #state{count=
      State#state.count+1}
    }.                         % update our state here

handle_info(Info, State) ->      % handle_info deals with out-of-band msgs, ie
    error_logger:info_msg("~p~n", [Info]), % msgs that weren't sent via cast
    {noreply, State}.          % or call. Here we simply log such messages.

terminate(_Reason, _State) ->  % terminate is invoked by the gen_server
    error_logger:info_msg("terminating~n"), % container on shutdown.
    ok.                        % we log it and acknowledge with ok.

code_change(_OldVsn, State, _Extra) -> % called during release up/down-
    {ok, State}.               % grade to update internal state. 

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
