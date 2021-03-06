%% @author Jesper Louis Andersen <jesper.louis.andersen@gmail.com>
%% @doc Main etorrent supervisor
%% <p>This Supervisor is the top-level supervisor of etorrent. It
%% starts well over 10 processes when it is initially started. It
%% will restart parts of etorrent, should they suddenly die
%% unexpectedly, but it is assumed that many of these processes do not die.</p>
%% @end
-module(etorrent_sup).

-behaviour(supervisor).

-include_lib("etorrent_core/include/supervisor.hrl").

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%% ====================================================================

%% @doc Start the supervisor
%% @end
-spec start_link(binary()) ->
			{ok, pid()} | ignore | {error, term()}.
start_link(PeerId) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [PeerId]).


%% ====================================================================

%% @private
init([PeerId]) ->
    lager:info("Etorrent supervisor starting, PeerId: ~p", [PeerId]),
    Conf         = ?CHILD(etorrent_config),
    Tables       = ?CHILD(etorrent_table),
    Torrent      = ?CHILD(etorrent_torrent),
    Tracker      = ?CHILD(etorrent_tracker),
    Counters     = ?CHILD(etorrent_counters),
    EventManager = ?CHILD(etorrent_event),
    PeerMgr      = ?CHILDP(etorrent_peer_mgr, [PeerId]),
    FastResume   = ?CHILD(etorrent_fast_resume),
    PeerStates   = ?CHILD(etorrent_peer_states),
    Choker       = ?CHILD(etorrent_choker),
    Console      = ?CHILD(etorrent_console),

    Listener     = {etorrent_listen_sup,
                    {etorrent_listen_sup, start_link, [PeerId]},
                    permanent, infinity, supervisor, [etorrent_listen_sup]},
    UdpTracking = {udp_tracker_sup,
                   {etorrent_udp_tracker_sup, start_link, []},
                   transient, infinity, supervisor, [etorrent_udp_tracker_sup]},
    TorrentPool = {torrent_pool_sup,
                   {etorrent_torrent_pool, start_link, []},
                   transient, infinity, supervisor, [etorrent_torrent_pool]},
    Ctl          = {etorrent_ctl,
                    {etorrent_ctl, start_link, [PeerId]},
                    permanent, 120*1000, worker, [etorrent_ctl]},
    DirWatcherSup = {dirwatcher_sup,
                  {etorrent_dirwatcher_sup, start_link, []},
                  transient, infinity, supervisor, [etorrent_dirwatcher_sup]},

    % Make the DHT subsystem optional
    DHTSup = case etorrent_config:dht() of
        false -> [];
        true ->
            [{dht_sup,
                {etorrent_dht_sup, start_link, []},
                permanent, infinity, supervisor, [etorrent_dht_sup]}]
    end,

    case etorrent_config:azdht() of
        false -> ok;
        true -> application:start(azdht)
    end,

    MDNSSup = case etorrent_config:mdns() of
        false -> [];
        true ->
            ListenIP = etorrent_config:listen_ip(),
            application:set_env(mdns, interface_ip, ListenIP),
            application:start(mdns),
            [{mdns_sup,
                {etorrent_mdns_sup, start_link, [PeerId]},
                permanent, infinity, supervisor, [etorrent_mdns_sup]}]
    end,

    %% UPnP subsystemm is optional.
    UPNPSup = case etorrent_config:use_upnp() of
        false -> [];
        true ->
            [{etorrent_upnp_sup,
                {etorrent_upnp_sup, start_link, []},
                permanent, infinity, supervisor, [etorrent_upnp_sup]}]
    end,

    {ok, {{one_for_all, 3, 60},
          [Conf, Tables, Torrent, Tracker,
           Counters, EventManager, PeerMgr,
           FastResume, PeerStates,
           Choker, Listener, UdpTracking] 
           ++ UPNPSup
           ++ DHTSup
           ++ MDNSSup
           ++ [TorrentPool, Ctl, DirWatcherSup, Console]}}.



