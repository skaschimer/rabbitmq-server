%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2025 Broadcom. All Rights Reserved. The term “Broadcom” refers to Broadcom Inc. and/or its subsidiaries. All rights reserved.
%%

-module(shovel_status_command_SUITE).

-include_lib("amqp_client/include/amqp_client.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile(export_all).

-define(CMD, 'Elixir.RabbitMQ.CLI.Ctl.Commands.ShovelStatusCommand').

all() ->
    [
      {group, non_parallel_tests}
    ].

groups() ->
    [
     {non_parallel_tests, [], [
                               run_not_started,
                               output_not_started,
                               run_starting,
                               output_starting,
                               run_running,
                               output_running,
                               e2e
        ]}
    ].

%% -------------------------------------------------------------------
%% Testsuite setup/teardown.
%% -------------------------------------------------------------------

init_per_suite(Config) ->
    rabbit_ct_helpers:log_environment(),
    Config1 = rabbit_ct_helpers:set_config(Config, [
        {rmq_nodename_suffix, ?MODULE}
      ]),
    Config2 = rabbit_ct_helpers:run_setup_steps(Config1,
      rabbit_ct_broker_helpers:setup_steps() ++
      rabbit_ct_client_helpers:setup_steps()),
    Config2.

end_per_suite(Config) ->
    rabbit_ct_helpers:run_teardown_steps(Config,
      rabbit_ct_client_helpers:teardown_steps() ++
      rabbit_ct_broker_helpers:teardown_steps()).

init_per_group(_, Config) ->
    Config.

end_per_group(_, Config) ->
    Config.

init_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_started(Config, Testcase).

end_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_finished(Config, Testcase).

%% -------------------------------------------------------------------
%% Testcases.
%% -------------------------------------------------------------------
run_not_started(Config) ->
    [A] = rabbit_ct_broker_helpers:get_node_configs(Config, nodename),
    Opts = #{node => A},
    {stream, []} = ?CMD:run([], Opts).

output_not_started(Config) ->
    [A] = rabbit_ct_broker_helpers:get_node_configs(Config, nodename),
    Opts = #{node => A},
    {stream, []} = ?CMD:output({stream, []}, Opts).

run_starting(Config) ->
    shovel_test_utils:set_param_nowait(
      Config,
      <<"test">>, [{<<"src-queue">>,  <<"src">>},
                   {<<"dest-queue">>, <<"dest">>}]),
    [A] = rabbit_ct_broker_helpers:get_node_configs(Config, nodename),
    Opts = #{node => A},
    case ?CMD:run([], Opts) of
        {stream, [{{<<"/">>, <<"test">>}, dynamic, starting, _, _}]} ->
            ok;
        {stream, []} ->
            throw(shovel_not_found);
        {stream, [{{<<"/">>, <<"test">>}, dynamic, {running, _}, _, _}]} ->
            ct:pal("Shovel is already running, starting could not be tested!")
    end,
    shovel_test_utils:clear_param(Config, <<"test">>).

output_starting(Config) ->
    [A] = rabbit_ct_broker_helpers:get_node_configs(Config, nodename),
    Opts = #{node => A},
    {stream, [#{vhost := <<"/">>, name := <<"test">>, type := dynamic,
                state := starting, last_changed := <<"2016-11-17 10:00:00">>,
                remaining := 10, remaining_unacked := 8,
                pending := 5, forwarded := 3}]}
        = ?CMD:output({stream, [{{<<"/">>, <<"test">>}, dynamic, starting,
                                 #{remaining => 10,
                                   remaining_unacked => 8,
                                   pending => 5,
                                   forwarded => 3},
                                 {{2016, 11, 17}, {10, 00, 00}}}]}, Opts),
    shovel_test_utils:clear_param(Config, <<"test">>).

run_running(Config) ->
    shovel_test_utils:set_param(
      Config,
      <<"test">>, [{<<"src-queue">>,  <<"src">>},
                   {<<"dest-queue">>, <<"dest">>}]),
    [A] = rabbit_ct_broker_helpers:get_node_configs(Config, nodename),
    Opts = #{node => A},
    {stream, [{{<<"/">>, <<"test">>}, dynamic, {running, _}, _,  _}]}
        = ?CMD:run([], Opts),
    shovel_test_utils:clear_param(Config, <<"test">>).

output_running(Config) ->
    [A] = rabbit_ct_broker_helpers:get_node_configs(Config, nodename),
    Opts = #{node => A},
    {stream, [#{vhost := <<"/">>, name := <<"test">>, type := dynamic,
                state := running, source := <<"amqp://server-1">>,
                destination := <<"amqp://server-2">>,
                termination_reason := <<>>,
                last_changed := <<"2016-11-17 10:00:00">>,
                remaining := 10,
                remaining_unacked := 8,
                pending := 5,
                forwarded := 3}]} =
        ?CMD:output({stream, [{{<<"/">>, <<"test">>}, dynamic,
                               {running, [{src_uri, <<"amqp://server-1">>},
                                          {dest_uri, <<"amqp://server-2">>}]},
                               #{remaining => 10,
                                 remaining_unacked => 8,
                                 pending => 5,
                                 forwarded => 3},
                               {{2016, 11, 17}, {10, 00, 00}}}]}, Opts),
    shovel_test_utils:clear_param(Config, <<"test">>).

e2e(Config) ->
    shovel_test_utils:set_param_nowait(
      Config,
      <<"test">>, [{<<"src-queue">>,  <<"src">>},
                   {<<"dest-queue">>, <<"dest">>}]),
    {ok, StdOut} = rabbit_ct_broker_helpers:rabbitmqctl(Config, 0, [<<"shovel_status">>]),
    [Msg, Headers0, Shovel0] = re:split(StdOut, <<"\n">>, [trim]),
    ?assertMatch(match, re:run(Msg, "Shovel status on node", [{capture, none}])),
    Headers = re:split(Headers0, <<"\t">>, [trim]),
    ExpectedHeaders = [<<"name">>, <<"vhost">>, <<"type">>, <<"state">>,
                       <<"source">>, <<"destination">>, <<"termination_reason">>,
                       <<"destination_protocol">>, <<"source_protocol">>,
                       <<"last_changed">>, <<"source_queue">>, <<"destination_queue">>,
                       <<"remaining">>, <<"remaining_unacked">>,
                       <<"pending">>, <<"forwarded">>],
    ?assert(lists:all(fun(H) ->
                              lists:member(H, Headers)
                      end, ExpectedHeaders)),
    %% Check some values are there
    ExpectedValues = [<<"test">>, <<"dynamic">>, <<"running">>],
    Shovel = re:split(Shovel0, <<"\t">>, [trim]),
    ?assert(lists:all(fun(V) ->
                              lists:member(V, Shovel)
                      end, ExpectedValues)),
    shovel_test_utils:clear_param(Config, <<"test">>).
