Title: Action components - how to package user actions in Geant4
Tags: geant4
    composite
    user actions
Summary: Building on the composite actions explained in a previous post, 
    here we introduce the "action components" that will be responsible
    for the creation of sub-actions at appropriate moments.

In a [previous post](/2016/02/05/composite_actions/) on composite actions,
I explained how it is possible to have multiple optional user action classes
of the same type in Geant4. However, this abstraction does not save us
from the necessity of initializing all these classes in appropriate methods
of a `G4VUserActionInitialization` descendant. Sometimes, there are 
further details we want to supply our actions with. I think this is perhaps
more than the "Action...ion" should know about the actions and their
internal workings. Sticking to the (almost always good) principle of 
encapsulation, let's package the actions inside action components and
design a `CompositeActionInitialization` class that will understand them.
The construction will be quite similar to that used
in the case of geometry components ([see another post](/2016/01/29/composite_geometry/)).

This time, we will not follow the bottom-up approach. Quite the opposite,
we will start from the requirements the `CompositeActionInitialization` class
will put on the components and then design our `ActionComponent` class.

## `CompositeActionInitialization` class

Again, our ultimate goal is to have an (abstract) class that knows nothing about 
the particular actions. Both the `Build()` and `BuildForMaster()` method
will just walk through the list of components, use them as if they were 
*mini*-action initializations in themselves and construct the respective
*composite actions*.

```c++
class CompositeActionInitialization {
public:
    void Build() override {
        auto runAction = new CompositeRunAction();
        auto eventAction = new CompositeEventAction();
        auto stackingAction = new CompositeStackingAction();
        auto trackingAction = new CompositeTrackingAction();
        auto steppingAction = new CompositeSteppingAction();

        for (auto component : fComponents) {
            if (!component->IsEnabled()) continue;

            auto actions = component->Build();           
            runAction->Add(actions.fRunAction);
            eventAction->Add(actions.fEventAction);
            stackingAction->Add(actions.fStackingAction);
            trackingAction->Add(actions.fTrackingAction);
            steppingAction->Add(actions.fSteppingAction);
        }

        if (!runAction->Empty()) SetUserAction(runAction);
        if (!eventAction->Empty()) SetUserAction(eventAction);
        if (!stackingAction->Empty()) SetUserAction(stackingAction);
        if (!trackingAction->Empty()) SetUserAction(trackingAction);
        if (!steppingAction->Empty()) SetUserAction(steppingAction);

        BuildPrimaryGeneratorAction();
    }

    void BuildForMaster() override {
        auto runAction = new CompositeRunAction();

        for (auto component : fComponents) {
            if (!component->IsEnabled()) continue;

            auto actions = component->BuildForMaster();
            runAction->Add(actions.fRunAction);
        }

        if (!runAction->Empty()) SetUserAction(runAction);
    }

    void AddComponent(ActionComponent* component) {
        fComponents.push_back(component);
    }

protected:
    virtual void BuildPrimaryGeneratorAction() = 0;

private:
    std::vector<ActionComponent*> fComponents;
};
```

Now, what is the type of `auto actions` in the loops inside the `Build...` methods?
Unfortunately, even with the wildest template magic, it is not easy (*at least for me*) to
pass several heterogenous object at once. We could possible use the `std::tuple` class
but this would put additional constraints on the *action components*. Therefore, 
we include another (very trivial) one-purpose struct `ActionSet`:

```c++
struct ActionSet
{
public:
    ActionSet() : fRunAction(nullptr), fEventAction(nullptr), fStackingAction(nullptr), fTrackingAction(nullptr), fSteppingAction(nullptr) { }

    // Templated constructors for convenience
    template <class T1> ActionSet(T1* t1) : ActionSet() { SetUserAction(t1); }
    template <class T1, class T2> ActionSet(T1* t1, T2* t2)
        : ActionSet(t1) { SetUserAction(t2); }
    template <class T1, class T2, class T3> ActionSet(T1* t1, T2* t2, T3* t3)
        : ActionSet(t1, t2) { SetUserAction(t3); }
    template <class T1, class T2, class T3, class T4> ActionSet(T1* t1, T2* t2, T3* t3, T4* t4) 
        : ActionSet(t1, t2, t3) { SetUserAction(t4); }
    template <class T1, class T2, class T3, class T4, class T5> ActionSet(T1* t1, T2* t2, T3* t3, T4* t4, T5* t5) 
        : ActionSet(t1, t2, t3, t4) { SetUserAction(t5); }

    // Setters for templates to work
    void SetUserAction(G4UserRunAction* action) { fRunAction = action; }
    void SetUserAction(G4UserEventAction* action) { fEventAction = action; }
    void SetUserAction(G4UserStackingAction* action) { fStackingAction = action; }
    void SetUserAction(G4UserTrackingAction* action) { fTrackingAction = action; }
    void SetUserAction(G4UserSteppingAction* action) { fSteppingAction = action; }

    // Publicly accessible fields
    G4UserRunAction* fRunAction;
    G4UserEventAction* fEventAction;
    G4UserStackingAction* fStackingAction;
    G4UserTrackingAction* fTrackingAction;
    G4UserSteppingAction* fSteppingAction;    
};
```

I challenge 


Then, in a concrete daughter class, 

(again, best in constructor) - the components should be designed so that they don't
create any action objects when created. 

Can keep a link to the component itself, but be aware of thread issues


```

```

## `ActionComponent` class


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