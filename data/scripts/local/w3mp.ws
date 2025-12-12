@addField(CR4Game)
var w3mStateMachine : W3mStateMachine;

@addMethod(CR4Game)
public function InitializeMultiplayer()
{
    if (!w3mStateMachine)
    {
        w3mStateMachine = new W3mStateMachine in this;
        w3mStateMachine.start();
    }
}

function StartMultiplayer() {
    theGame.InitializeMultiplayer();
}

struct W3mPlayerState
{
    var angles : EulerAngles;
    var position : Vector;
    var velocity : Vector;
    var speed : float;
    var moveType : int;
}

struct W3mPlayer
{
    var guid : Uint64;
    var playerName : string;
    // Always has 1 entry. Technically the array is not needed
    // The idea is only to force proper alignment of the playerState.
    // The W3mPlayerState struct seems to be wrongly aligned (4 instead of 16) when being a member 
    var playerState : array<W3mPlayerState>;
}

struct W3mTrackedPlayer
{
    var guid : Uint64;
    var entity : CEntity;
    var lastUpdate : float;
}

import function W3mPrint(msg : string);
import function W3mSetNpcDisplayName(npc : CNewNPC, npcName : string);
import function W3mStorePlayerState(playerState : W3mPlayerState);
import function W3mGetPlayerStates() : array<W3mPlayer>;
import function W3mUpdatePlayerName(playerName : string);
import function W3mGetMoveType(movingAgent : CMovingAgentComponent) : int;
import function W3mSetSpeed(movingAgent : CMovingAgentComponent, absSpeed: float);

function ConvertToMoveType(moveType : int) : EMoveType
{
    switch(moveType)
    {
        case 0:
            return MT_Walk;
            
        case 1:
            return MT_Run;	

        case 2:
            return MT_FastRun;
            
        case 3:
            return MT_Sprint;

        case 4:
            return MT_AbsSpeed;

        default:
            return MT_Walk;
    }
}

function TransmitPlayerState(actor : CActor)
{
    var playerState : W3mPlayerState;
    var movingAgent : CMovingAgentComponent;

    movingAgent = actor.GetMovingAgentComponent();

    playerState.position = actor.GetWorldPosition();
    playerState.angles = actor.GetWorldRotation();
    playerState.velocity = movingAgent.GetVelocity();
    playerState.speed = movingAgent.GetSpeed();
    playerState.moveType = W3mGetMoveType(movingAgent);

    W3mStorePlayerState(playerState);
}

function TransmitCurrentPlayerState()
{
    TransmitPlayerState((CActor)thePlayer);
}

function ApplyPlayerState(actor : CActor, player : W3mPlayer)
{
    var movingAgent : CMovingPhysicalAgentComponent;
    var actorPos : Vector;
    var targetPos : Vector;
    var playerState : W3mPlayerState;
    var angleHeading : float;
    var dist : float;

    if (player.playerState.Size() < 1)
    {
        return;
    }

    playerState = player.playerState[0];

    W3mSetNpcDisplayName((CNewNPC)actor, player.playerName);

    actorPos = actor.GetWorldPosition();
    targetPos = playerState.position;

    if (AbsF(actorPos.Z -  targetPos.Z) < 0.25)
    {
        targetPos.Z = actorPos.Z;
    }

    movingAgent = (CMovingPhysicalAgentComponent)actor.GetMovingAgentComponent();

    dist = VecDistance(actorPos, targetPos);

    if (dist > 1.0)
    {
        actor.TeleportWithRotation(targetPos, playerState.angles);
    }
    else
    {
        movingAgent.ApplyVelocity(playerState.velocity);
    }

    angleHeading = VecHeading(RotForward(playerState.angles));

    movingAgent.SetMoveType(ConvertToMoveType(playerState.moveType));
    movingAgent.SetGameplayMoveDirection(angleHeading);

    W3mSetSpeed(movingAgent, playerState.speed);
}

function AddAndEquip(npc: CNewNPC, item: name) {
    var ids : array<SItemUniqueId>;

    ids = npc.GetInventory().AddAnItem(item, 1);
    npc.EquipItem(ids[0]);
}

function CreateNewPlayerEntity() : CEntity
{
    var pos : Vector;
    var rot : EulerAngles;
    var ent : CEntity;
    var npc : CNewNPC;
    var template : CEntityTemplate;
    var followerMovingagent : CMovingAgentComponent;
    var followOnFootAI : CAIFollowSideBySideAction;
    var tags : array<name>;


    tags.PushBack('w3m_Player');

    rot = thePlayer.GetWorldRotation();	
    pos = thePlayer.GetWorldPosition();

    template = (CEntityTemplate)LoadResource("characters/npc_entities/main_npc/geralt_npc.w2ent", true);

    ent = theGame.CreateEntity(template, pos, rot,,,,,tags);
    npc = (CNewNPC)ent;

    AddAndEquip(npc, 'Autogen steel sword');
    AddAndEquip(npc, 'Autogen silver sword');
    AddAndEquip(npc, 'Autogen Pants');
    AddAndEquip(npc, 'Autogen Gloves');
    AddAndEquip(npc, 'Autogen Boots');
    AddAndEquip(npc, 'Autogen Armor');
    AddAndEquip(npc, 'Shaved With Tail Hairstyle');
    AddAndEquip(npc, 'head_3');

    npc.AddAbility('_canBeFollower', true); 

    followerMovingagent = npc.GetMovingAgentComponent();
    followerMovingagent.SetGameplayRelativeMoveSpeed(0.0f);
    followerMovingagent.SetDirectionChangeRate(0.16);
    followerMovingagent.SetMaxMoveRotationPerSec(60);
    
    npc.GotoState('NewIdle', false);

    W3mSetNpcDisplayName(npc, "W3M Player");

    npc.SetAttitude(thePlayer, AIA_Neutral);

    return ent;
}

statemachine class W3mStateMachine extends CEntity
{
    editable var trackedPlayers : array<W3mTrackedPlayer>;

    public function start()
    {
        this.GotoState('MultiplayerState');
    }
}

state MultiplayerState in W3mStateMachine
{
    event OnEnterState(previous_state_name: name)
    {
        this.EntryFunction();
    }

    entry function EntryFunction()
    {
        this.RunMultiplayer();
    }

    latent function RunMultiplayer()
    {
        while(true)
        {
            RunMultiplayerFrame();
            Sleep(0.001);
        }
    }

    latent function RunMultiplayerFrame()
    {
        TransmitCurrentPlayerState();
        UpdateOtherPlayers();
    }

    latent function UpdateOtherPlayers()
    {
        var i, j : int;
        var player_states : array<W3mPlayer>;
        var found : bool;
        var tracked : W3mTrackedPlayer;
        var currentTime : float;

        currentTime = theGame.GetEngineTimeAsSeconds();
        player_states = W3mGetPlayerStates();

        for (i = 0; i < player_states.Size(); i += 1)
        {
            found = false;
            for (j = 0; j < parent.trackedPlayers.Size(); j += 1)
            {
                if (parent.trackedPlayers[j].guid == player_states[i].guid)
                {
                    ApplyPlayerState((CActor)parent.trackedPlayers[j].entity, player_states[i]);
                    parent.trackedPlayers[j].lastUpdate = currentTime;
                    found = true;
                    break;
                }
            }

            if (!found)
            {
                tracked.guid = player_states[i].guid;
                tracked.entity = CreateNewPlayerEntity();
                tracked.lastUpdate = currentTime;

                ApplyPlayerState((CActor)tracked.entity, player_states[i]);
                parent.trackedPlayers.PushBack(tracked);
            }
        }

        for (i = parent.trackedPlayers.Size() - 1; i >= 0; i -= 1)
        {
            if (parent.trackedPlayers[i].lastUpdate != currentTime)
            {
                parent.trackedPlayers[i].entity.Destroy();
                parent.trackedPlayers.Erase(i);
            }
        }
    }
}

function DisplayFeedMessage(msg: string)
{
    var hud : CR4ScriptedHud;
    
    hud = (CR4ScriptedHud)theGame.GetHud();
    if (hud)
    {
        hud.HudConsoleMsg(msg);
    }
}

function DisplayCenterMessage(msg: string)
{
    GetWitcherPlayer().DisplayHudMessage(msg);
}

exec function SetName(playerName: string)
{
    W3mUpdatePlayerName(playerName);
    DisplayFeedMessage("Name changed: " + playerName);
}

exec function w3m_list()
{
    var states : array<W3mPlayer>;
    var i : int;

    states = W3mGetPlayerStates();
    DisplayFeedMessage("Connected players: " + states.Size());
    
    for(i=0; i<states.Size(); i+=1)
    {
        DisplayFeedMessage("#" + i + ": " + states[i].playerName + " [" + states[i].guid + "]");
    }
}

exec function w3m_tp(nameStr : string)
{
    var states : array<W3mPlayer>;
    var i : int;
    var pos : Vector;
    var rot : EulerAngles;

    states = W3mGetPlayerStates();
    
    for(i=0; i<states.Size(); i+=1)
    {
        if (states[i].playerName == nameStr)
        {
           if (states[i].playerState.Size() > 0)
           {
               pos = states[i].playerState[0].position;
               rot = states[i].playerState[0].angles;
               thePlayer.TeleportWithRotation(pos, rot);
               DisplayFeedMessage("Teleported to " + nameStr);
               return;
           }
        }
    }
    DisplayFeedMessage("Player not found: " + nameStr);
}

exec function w3m_unstuck()
{
    var pos : Vector;
    pos = thePlayer.GetWorldPosition();
    pos.Z += 3.0;
    thePlayer.Teleport(pos);
    DisplayFeedMessage("Unstuck!");
}
