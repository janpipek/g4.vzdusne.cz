Title: Remote control of Geant4 application over HTTP
Tags: geant4
    http
    remote
    json
Summary: Run a Geant4 application, use one of your favourite 
    programming language to control it remotely
    using this HTTP + JSON simple API.

If you want to control a Geant4 application,
you can either write macro files or use its UI (terminal
or graphical). None of these methods is easily scriptable
(imagine you would like to optimize some parameter and execute
thousands of runs iteratively). In this post, I describe how
you can easily achieve this using a simple HTTP server and
JSON API.

Let's start with the functionality (API) our server will provide;
then we will continue with the implementation and finally...
- python / matlab???

## API overview

The server accepts three different GET requests (you can therefore
easily test everything in your browser, although `/command` is semantically
closer to a POST request). All responses are formatted in JSON.

### /appState

This returns the status of the application as a state machine
(see 3.4.2 of the [application developer guide](https://geant4.web.cern.ch/geant4/UserDocumentation/UsersGuides/ForApplicationDeveloper/html/ch03s04.html#sect.Run.StateMac)).

Example output (http://localhost:6464/appState):

```json
{ "state" : 0, "message": "PreInit"}
```

Note: It is not easy to distinguish between `GeomClosed` and `EventProc` states
from the master thread. So, `EventProc` is never returned even when
a run is being executed.

### /command

Example output (http://localhost:6464/command?cmd=%2Frun%2Finitialize):

```json
{ "id" : 0}           
```

The command is not executed synchronously because it may take quite long
to execute (like `/run/beamOn 1000000000` :-)). Therefore, the user
just obtains an ID and 

### /status

Given `id` parameter (command number), this request will return the status of the command
and some server message.

```json
{ "status" : 0, "message" : "OK" }
{ "status" : -3, "message" : "Unknown command" }
{ "status" : 500, "message" : "Parameter out of canidated" }
```



## HTTP Server

In principle,  

I have some positive (although limited) experience with the **web++**
server by Alex Movsisyan. You can find the original version of this single-header-file
library here: <http://konteck.github.io/wpp/>. However, the following text
will be based on my fork, that includes a few important updates: <https://github.com/janpipek/wpp>.

## HTTP Session

```c++
namespace { G4Mutex commandMutex = G4MUTEX_INITIALIZER; }

using namespace std;

HttpSession::HttpSession(G4int port, G4int verbosity)
    : fVerbosity(verbosity), fPort(port), fSleepInterval(1000000), fLastCommandQueued(-1), fLastCommandExecuted(-1)
{
    if (!G4Threading::IsMasterThread())
    {
        G4Exception("HttpSession", "NoMasterThread", FatalException, "Cannot initialize HttpSession outside the master thread");
    }
    fGlobalStateManager = G4StateManager::GetStateManager();    // Steal thread-local variable.
    fServer = make_shared<HttpServer>(this);
}

void HttpSession::SessionStart() {
    fServer->Start();
    G4UImanager* UImanager = G4UImanager::GetUIpointer();

    while (true) {               // Infinite loop, interruptible by Ctrl-C
        G4String command;
        if (!PopCommand(command)) {
            usleep(fSleepInterval);
            continue;
        }
        else {
            fCommandStatus.push_back(EXECUTING);
            G4int result = UImanager->ApplyCommand(command);
            fLastCommandExecuted++;
            fCommandStatus[fLastCommandExecuted] = result;
        }
    }
}

G4int HttpSession::QueueCommand(G4String command) {
    G4AutoLock lock(&commandMutex);
    if (command.empty())
    {
        return -1;
    } else {
        fCommandQueue.push_back(command);
        return ++fLastCommandQueued;
    }
}

G4ApplicationState HttpSession::GetApplicationState()
{
    G4ApplicationState state = fGlobalStateManager->GetCurrentState();
    return state;
}

G4int HttpSession::GetCommandStatus(G4int commandId) {
    G4AutoLock lock(&commandMutex);
    if ((fLastCommandQueued < commandId) || (commandId < 0)) {
        return UNKNOWN;
    }
    else if (fLastCommandExecuted < commandId) {
        return QUEUED;
    }
    else {
        return fCommandStatus[commandId];
    }
}

G4String HttpSession::GetCommandStatusDescription(G4int status) {
    // Simple statuses
    switch(status) {
    case fCommandSucceeded:
        return "OK";
    case QUEUED:
        return "Queued";
    case EXECUTING:
        return "Executing";
    case UNKNOWN:
        return "Unknown command";
    }

    // More complicated status
    G4int major = (status / 100) * 100;
    G4int minor = status - major;
    switch(major)
    {
    case fCommandNotFound:
        return "Command not found";
    case fIllegalApplicationState:
        return "Illegal application state";
    case fParameterOutOfRange:
        return "Parameter out of range";
    case fParameterUnreadable:
        return "Parameter unreadable";
    case fParameterOutOfCandidates:
        return "Parameter out of canidated";
    case fAliasNotFound:
        return "Alias not found";
    default:
        return "Unknown status";
    }
}

G4bool HttpSession::PopCommand(G4String& commandRef) {
    G4AutoLock lock(&commandMutex);
    if (fCommandQueue.empty()) {
        return false;
    }
    else {
        commandRef = fCommandQueue.front();
        fCommandQueue.pop_front();
        return true;
    }
}
```

## Command queue

It is not possible to execu

- synchronized (mutex-protected)

- input: from 

Note: After your running application executes ~10^8
commands, you may observe it's memory imprint rising a bit.

## Security warning

I must warn you not to 
ever use the described method on a computer accessible
from a public network and listening on any non-local
IP address. The protocol presented in this article allows
to execute arbitrary macro commands in Geant4, including
the powerful `/control/shell`.

- trust users - port

- the implementation of HTTP server simple, not military-class.

## Random notes

**Why didn't I sub-class `G4UIsession` or any other class
responsible for UI?** Honestly, the *intercoms* category classes 
seem a bit incomprehensible to me. I believe that my method
could be implemented in more Geant4-ish way, but I was just lazy to do so
(you are welcome to continue where I stopped).

**Why not wt?** I didn't want a web user interface, I wanted
a simple API for my scripting needs.

## Other possibilities

- wt

- zmq

- jupyter

## How to connect