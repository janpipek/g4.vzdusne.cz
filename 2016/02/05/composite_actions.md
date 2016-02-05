Title: Multiple user actions of the same type in Geant4
Tags: geant4
    composite
    user actions
Summary: Say you have two different user stepping action classes
    and use them both without merging them into one object. This
    is by default impossible in Geant4. In this post, I explain how
    you can do that employing *composite actions* and *action components*.



[Section 6.2](http://geant4.web.cern.ch/geant4/UserDocumentation/UsersGuides/ForApplicationDeveloper/html/ch06s02.html)

There are five such classes:

* `G4UserSteppingAction`

* `G4UserTrackingAction``.

* `G4UserEventAction`

* `G4UserStackingAction`

* `G4UserRunAction`

`G4VUserPrimaryGeneratorAction` is a `G4VUserPrimaryGeneratorAction` but we will call
it l'`G4VUserPrimaryGeneratorAction`. According to me, a composite `G4VUser­Primary­Generator­Action`
does not make much sense.

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

Now that we have a general structure, that does not do much itself, we have to define a composite alternative to each of the five basic user actions. We need to override all relevant
virtual methods and implement a specific "composite behaviour"
in them. In most cases,
we will just iterate through all sub-actions and call the eponymous methods one
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

**...and stop!** We are getting to the last two classes that both
have their little peculiarities. Until now, it was possible to
run all the sub-action methods without causing interference.

The `G4UserStackingAction` defines a virtual method `ClassifyNewTrack` that
has a return value! This means
our overriding implementation also has to return
a value - but what value when we can are provided with more
of them? Obviously, we cannot change the API and return a vector.
My chosen approach is to assume the default value (i.e. `fUrgent`)
and become interested only when a sub-action returns something different.
If all sub-actions agree on a single non-default value (default values
are ignored), we return it. If they disagree, there is a conflict
which is not easy to solve consistently and the safest approach is
to generate a `G4Exception`. Anyway, at most times, you should
avoid returning a non-default value unless you are really sure
about what you're doing.

Here is the code:

```c++
class CompositeStackingAction : public CompositeAction<G4UserStackingAction> {
public:
    G4ClassificationOfNewTrack ClassifyNewTrack(const G4Track* aTrack) override {
        G4ClassificationOfNewTrack classification = fUrgent;
        for (auto action : fSubActions) {
            G4ClassificationOfNewTrack newClassification = action->ClassifyNewTrack(aTrack);
            if (newClassification != fUrgent) {
                if ((classification != fUrgent) && (classification != newClassification)) {
                    G4Exception("ClassifyNewTrack", "Incompatible classifications",
                        FatalException, "Cannot have two different non-urgent classifications.");
                }
                else {
                    classification = newClassification;
                }
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
There are two issues here:

* Its `GenerateRun` method may (but doesn't need to) return a `G4Run` object.
Using approach already employed in the previous case, we will not let two
different sub-actions return a customized `G4Run` object (which of them would be
the correct one?). If just one sub-action does that, we happily return it.
Otherwise we return (as is the default) `nullptr`. Personally, I don't recommend
to implement `GenerateRun` in sub-actions.

* The run action has an `IsMaster` method. It is useful in multi-threaded regime
when you have to distinguish between the master and worker runs. Unfortunately,
this information is set for the run action from outside (using `SetMaster`) and only before the
`GenerateRun`. Therefore, we also forward this information in our implementation.

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
