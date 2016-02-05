Title: Multiple user actions of the same type in Geant4
Tags: geant4
    composite
    user actions
Summary: Say you have two different user stepping action classes
    and use them both without merging them into one object. This
    is by default impossible in Geant4. In this post, I explain how
    you can do that employing *composite actions* and *action components*.

It is usually a bad thing.

The issue is even more complicated when

* not considering primary generator

## Abstract composite action

```c++
template<typename ActionType> class CompositeAction : public ActionType {
public:
    using actionType = ActionType;

    void Add(ActionType* action) {
        if (!action) {
            return;
        }
        if (find(fSubActions.begin(), fSubActions.end(), action) == fSubActions.end()) {
            fSubActions.push_back(action);
        }
    }

    void Remove(ActionType* action) {
        // Erases just one (first) copy of the action.
        auto it = find(fSubActions.begin(), fSubActions.end(), action);
        if (it != fSubActions.end()) {
            fSubActions.erase(it);
        }
    }

    bool Empty() const { return fSubActions.empty(); }

protected:
    std::list<ActionType*> fSubActions;
};
```

## Concrete classes

Now that we have a general structure, that does not do much itself, we have to
define a composite alternative to each of the five basic user actions that adds
the specific behaviour by overriding the relevant virtual methods. Usually,
we just iterate through all sub-actions and call the eponymous methods one
after another (they are usually not in conflict).

Let's start with the `G4UserSteppingActions` class. This declares (and defines)
just one virtual method. It is therefore quite easy to implement its composite
variant:

```c++
class CompositeSteppingAction : public CompositeAction<G4UserSteppingAction> {
public:
    void UserSteppingAction(const G4Step* step) override {
        for (auto action : fSubActions) {
            action->UserSteppingAction(step);
        }
    }
};
```

In a similar way, we continue with `G4UserTrackingAction` that
contains two virtual methods (with no added complexity)...

```c++
class CompositeTrackingAction : public CompositeAction<G4UserTrackingAction> {
    void PreUserTrackingAction(const G4Track* track) override {
        for (auto action : fSubActions) {
            action->PreUserTrackingAction(track);
        }
    }

    void PostUserTrackingAction(const G4Track* track) override {
        for (auto action : fSubActions) {
            action->PostUserTrackingAction(track);
        }
    }  
};
```

...and `G4UserEventAction`...

```c++
class CompositeEventAction : public CompositeAction<G4UserEventAction> {
public:
    void BeginOfEventAction(const G4Event* anEvent) override {
        for (auto action : fSubActions) {
            action->BeginOfEventAction(anEvent);
        }
    }

    void EndOfEventAction(const G4Event* anEvent) override {
        for (auto action : fSubActions) {
            action->EndOfEventAction(anEvent);
        }
    }
};
```

**Stop!** We are getting to the last two classes that both
have their little peculiarities. Until now, it was possible to
run all the sub-action methods without causing interference.


```c++
class CompositeStackingAction : public CompositeAction<G4UserStackingAction> {
public:
    G4ClassificationOfNewTrack ClassifyNewTrack(const G4Track* aTrack) override {
        G4ClassificationOfNewTrack classification = fUrgent;
        for (auto action : fSubActions) {
            classification = action->ClassifyNewTrack(aTrack);
            if (classification != fUrgent) {
                break;
            }
        }
        return classification;
    }

    void NewStage() override {
        for (auto action : fSubActions) {
            action->NewStage();
        }
    }

    void PrepareNewEvent() override {
        for (auto action : fSubActions) {
            action->PrepareNewEvent();
        }
    }    
};
```

...and last but not least, the trickiest action class, the `G4UserRunAction`.

```c++
class CompositeRunAction : public CompositeAction<G4UserRunAction> {
public:
    G4Run* GenerateRun() override {
        G4Run* run = nullptr;
        for (auto action : fSubActions) {
            action->SetMaster(IsMaster());
            G4Run* newRun = action->GenerateRun();
            if (run && newRun) {
                G4Exception("GenerateRun", "Duplicity",
                    FatalException, "Cannot generate a run in two different sub-actions.");
            }
            else {
                run = newRun;
            }
        }
        return run;
    }

    void BeginOfRunAction(const G4Run* aRun) override {
        for (auto action : fSubActions) {
            action->BeginOfRunAction(aRun);
        }
    }

    void EndOfRunAction(const G4Run* aRun) override {
        for (auto action : fSubActions) {
            action->EndOfRunAction(aRun);
        }
    }    
};
```

## Notes

* Recently, I found that there is

## Disclaimer

This post is based on the work I have done for the ELIMED project
(closed-source) and also on my library g4application (open-source, see <https://github.com/janpipek/g4application>) -
both projects employ a variant of the presented concept.
