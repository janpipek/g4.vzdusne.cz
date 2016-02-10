Title: Action components - how to package user actions in Geant4
Tags: geant4
    composite
    user actions
Summary: Building on the composite actions explained in a previous post, 
    here we introduce the "action components" that will be responsible
    for the creation of sub-actions at appropriate moments.

In a [previous post](/2016/02/05/composite_actions/) on composite actions,
I explained how it is possible to have multiple optional user action classe
of the same type in Geant4. However, this abstraction does not saves us
from the necessity of initializing all these classes

  . The construction will be quite similar to that used
in the case of geometry components ([see another post](/2016/01/29/composite_geometry/))

Today, we will not follow the bottom-up approach. Quite the opposite,
we will start with the requirement. 

## `CompositeActionInitialization` class


AddComponent()

Build()

BuildForMaster()



Then, in a concrete daughter class, 

(again, best in constructor) - the components should be designed so that they don't
create any action objects when created. 

Can keep a link to the component itself, but be aware of thread issues


```

```


There must be some kind of interface to pass all necessary action classes...

Unfortunately, impossible in separate methods

No object outside the component directly knows about the action - therefore
all important parameters should be kept in the component and actions rather
lightweight <-- change this



## What about the 

l'... 



## Example: event monitoring

One of the typical functionalities developers usually want to include in their
Geant4 application, is the ability to track the simulation progress, e.g. by
printing from time to time (with user-specified frequency) the number of event
currently being processed. This calls for a simple `G4UserEventAction`. If we want to package it in
an action component, let's do it like this:

```c++
class EventMonitoringEventAction : public G4UserEventAction
{
public:
    EventMonitoringEventAction(const EventMonitoringComponent& component) : fComponent(component) { }

    void BeginOfEventAction(const G4Event* anEvent) override {
        if (anEvent->GetEventID() % fComponent.GetFrequency() == 0) {
            G4cout << "Event #" << anEvent->GetEventID() << " started." << G4endl;
        }
    }

private:
    const EventMonitoringComponent& fComponent;
};

class EventMonitoringComponent : public ActionComponent
{
public:
    ActionSet Build() const override {
        ActionSet set;
        set.SetUserAction(new EventMonitoringEventAction(*this));
        return set;
    }

    void SetFrequency(G4int frequency) { fFrequency = frequency; }

    G4int GetFrequency() const { return fFrequency; }

private:
    G4int fFrequency;
};

```

Then in our action initialization, we just create an instance of the component
and perhaps set the frequency (which will be stored in the component, not the action):

```c++
OurActionInitialization::OurActionInitialization() {
    auto eventMonitoring = new EventMonitoringComponent();
    eventMonitoring->SetFrequency(100);
    AddComponent(eventMonitoring);

    // Add other components
}
```


## Further comments

* No G4RunManager approach (< 10)

## Disclaimer

This post is based on the work I have done for the ELIMED project
(closed-source) and also on my library g4application (open-source, see <https://github.com/janpipek/g4application>) -
both projects employ a variant of the presented concept.