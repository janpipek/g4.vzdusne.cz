Title: Multiple user action classes of the same type in Geant4
Tags: geant4
    composite
    user actions
Summary: How is it possible to use two (or more) different
    user action classes of the same type (e.g. `G4UserSteppingAction`)
    despite the fact that Geant4 allows to register just one object
    of each type? The answer is the concept of a "composite action".

In any reasonable Geant4 application, you will need to implement one or more
*optional user action classes* (see [Section 6.2](http://geant4.web.cern.ch/geant4/UserDocumentation/UsersGuides/ForApplicationDeveloper/html/ch06s02.html)
of the application developer guide). There are five such classes:

* `G4UserSteppingAction`;

* `G4UserTrackingAction`;

* `G4UserEventAction`;

* `G4UserStackingAction`;

* `G4UserRunAction`.

However, say that you need two different stepping actions that do totally unrelated
things. Of course, you can combine their behaviour by putting all code in one method.
Or, better, you can use some (more or less sophisticated) way to keep the behaviour separate
and at the same time satisfy Geant4's requirement to have just one instance of each
action type.

Here, I generalize the second approach in a way that allows you to really have multiple
action classes of each type in your application without them being aware that they are not treated
as a single privileged object. This abstraction involves a **composite action** class
that serves as a dispatcher for a set of different **sub-actions**. Though the concept is
quite simple, I believe it can make Geant4 developer's life a bit easier. I also
deal with some of the less obvious implications in the following text.

A picture at the beginning (hopefully) shows what class hierarchy we want to build:

![uml](schema.svg "Simplified UML diagram")

## Abstract composite action

We begin with defining an abstract (and templated) class called `CompositeAction` that
will serve as the base class for the five composite classes that are our ultimate goal.
If you look at its definition, it's little more than a simple container that inherits
from its own item type. The last point is very important -- it enables you to treat the container
as if it were a single instance of the base class (which is what `G4RunManager` wants).

*Note: There is no destructor to delete the action objects. This
would come handy in most cases but would pose problems in cases where object
ownership is more complex (one way out of this is to consistently use smart pointers
which is a topic far beyond the scope of this document). Therefore, we let the user
deal with memory management (e.g. by letting all object die when the application
is ended; usually the resulting memory leak is not a big deal.)*

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

At this moment, we could already instantiate a realization of this class template
-- like `CompositeAction<G4UserSteppingAction>` -- but it would not do anything;
the default implementations of the important virtual methods are empty. We now
have to override them all and implement "composite behaviour" in them, eventually
creating five concrete classes ready to be used in an application.
In most implementations, we will just iterate through all sub-actions and call
the eponymous methods one after another (they are usually not in conflict).
There are a few catches which I will discuss.

## Concrete classes

Let's start with the `G4UserSteppingAction` class. This declares (and defines)
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
a value - but what value when we are provided with more
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
                    G4Exception("ClassifyNewTrack", "IncompatibleClassifications",
                        FatalException,
                        "Cannot have two different non-urgent classifications.");
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

* Its `GenerateRun` method may (but is not required to) return a `G4Run` object.
Using approach already employed in the previous case, we will not let two
different sub-actions return a customized `G4Run` object (which of them would be
the correct one?). If just one sub-action does that, we happily return it.
Otherwise we return (as is the default) `nullptr`. Personally, I don't recommend
to implement `GenerateRun` in sub-actions (you would be better to do that in your
custom CompositeRunAction).

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
                G4Exception("GenerateRun", "Duplicity", FatalException,
                    "Cannot generate a run in two different sub-actions.");
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

And this is pretty much it.

## Further steps

You can implement your sub-actions and compose them in `Build` and `BuildForMaster`
methods of your `G4VUserActionInitialization` class (or register them using
`G4RunManager` if you still use the old-fashioned single-threaded approach). This
is perfectly possible and I believe your application becomes much better structured
just by doing so.

However, to make the separation complete, I propose another layer of abstraction
consisting of "action components" that package related user actions together
and keep the non-related actions as separate as possible. This will become a topic
of a future blog post.

## Random notes

* Recently, I found that it is possible to assign a "regional" `G4UserSteppingAction`
to a specific `G4Region` using the `SetRegionalSteppingAction` method. However, I have
not yet found any proper documentation for it.

* Because the composite alternative of an action class inherits from its item class,
it *is* the item class, so you can create a tree hierarchy of composite actions;
not that I see any sense in that...

## Disclaimer

This post is based on the work I have done for the ELIMED project
(closed-source) and also on my library g4application (open-source, see <https://github.com/janpipek/g4application>) -
both projects employ a variant of the presented concept.
