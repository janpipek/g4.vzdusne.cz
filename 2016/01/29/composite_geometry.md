Title: Geant4 detector construction from independent components
Tags: geometry
    geant4
    composite
Summary: How to divide detector construction into several independent parts? Let's
    separate it into "geometry components" and construct a "composite geometry".

In Geant4, you are supposed to develop a single class responsible
for the whole detector construction (a.k.a. geometry); it has to inherit from
`G4VUserDetectorConstruction` and everything should happen or at
least should be initiated from its `Construct` and possibly
`ConstructSDandField` methods (see [Section 6.1.1](http://geant4.web.cern.ch/geant4/UserDocumentation/UsersGuides/ForApplicationDeveloper/html/ch06.html#sect.DetConst) of the application developer guide).

This makes sense from the point of view of the run manager as a consumer
of the class, but according to my experience, it does not always lead to
good code, especially when a complex and/or flexible detector
setup is necessary. Too often, the code revolves around the
central ("god-like") class and different parts of the geometry
end up intertwined and inseparable from each other; moreover
this occurs in several places: the private data members of the class,
the public methods to set parameters, and also in both
mentioned methods.

Now imagine you want to take one part of the detector (say a radiochromic film layer)
and temporarily remove it from the setup. Or perhaps reuse it in another application.
What will you do? What lines of code will you need to change or comment out?

## What is the ideal?

In order to circumvent all these complications and to have a clear
application structure, I propose the concept of **component**.
A component is an object that describes, as independently of the rest
of the application as possible, a single part of the geometry.

The whole design then follows these guidelines:

* All components inherit from a common abstract base class, `DetectorComponent`, that
contains shared functionality (which is not very wide).

* The mechanism for combining components should be implemented
in an abstract base class that does not involve any concrete geometry.
Let's call it `CompositeDetectorConstruction`. This class could be included
in whatever application without a change.

* In a specific detector construction class of the application
that will inherit from `CompositeDetectorConstruction`, each
component should be just instantiated and perhaps positioned
(both in one place).

* This specific class has to be registered to the application's run
manager as usual.

See a UML diagram:

![uml](diagram.png "Simplified UML diagram")

## The DetectorComponent class

What should a component do? In a way, it is a mini-detector construction in itself.
So, we should definitely define `Construct` and `ConstructSDandField` methods for it.
Following the detector construction, `Construct` is pure virtual (abstract) and you have
to override it, `ConstructSDandField` has a default (trivial) implementation.

Be aware that the signature of `Construct` is different from detector construction!
The component won't be responsible for creating its physical volume and therefore
it returns a logical volume instead of a physical one.

We will just keep the *name*, *position* (and potentially *rotation*,
which we won't deal with for simplicity) as data members (with setters and getters). In addition, we will also implement a simple mechanism for fast *enabling* and *disabling* of the component.

This leaves the class definition (not split into header & source files) quite simple:

```c++
class DetectorComponent
{
public:
    DetectorComponent(G4String& name)
        : fName(name), fEnabled(true), fPosition({0.0, 0.0, 0.0}) { }
    virtual ~DetectorComponent() = default;

    virtual G4LogicalVolume* Construct() = 0;    // overriding compulsary
    virtual void ConstructSDandField() { }       // default implementation

    const G4String& GetName() const { return fName; }

    const G4ThreeVector& GetPosition() const { return fPosition; }
    void SetPosition(const G4ThreeVector& pos) { fPosition = pos; }

    G4bool IsEnabled() const { return fEnabled; }

    // Note that once the detector is constructed, this has no effect!
    void SetEnabled(G4bool enabled) { fEnabled = enabled; }

private:
    G4String fName;
    G4bool fEnabled;
    G4ThreeVector fPosition;    
}
```

For simplicity, I don't define a *messenger* for the class (it is a trivial step)
or deal with the possibility of a component becoming *sub-component* of another volume
(this is also possible but I do not want to complicated this text too much). Nor
do I add the above mentioned *rotation* which can be handled in a way similar to
position (there is a couple of caveats though).

## The CompositeDetectorConstruction class

This class is a general container for component classes. Its role
is to accumulate the components at an appropriate moment (I would
prefer to do so in the constructor of its child class) and to distribute its responsibilities
among these components.

In both its required methods, i.e. `Construct` (called once) and
`ConstructSDandField` (called for each worker thread), we iterate (please, forgive my C++11)
over the components and call methods of the same name on them
(provided the component is not disabled).

Note that before creating component physical volumes, we need
to have a world volume to become their parent. Therefore, there
is an abstract protected method `ConstructWorldVolume` which you
have to implement in the child class.

```c++
class CompositeDetectorConstruction : public G4VUserDetectorConstruction
{
public:
    G4VPhysicalVolume* Construct() override
    {
        fPhysicalWorld = ConstructWorldVolume();
        for (auto component : fComponents)
        {
            if (!component->IsEnabled()) continue;
            G4LogicalVolume* log = component->Construct();
            new G4PVPlacement(
                nullptr,
                component->GetPosition(),
                log,
                component->GetName(),
                fPhysicalWorld->GetLogicalVolume(),
                false,
                0
            )
        }
    }

    void ConstructSDandField() override
    {
        for (auto component : fComponents)
        {
            if (!component->IsEnabled()) continue;
            component->ConstructSDandField();
        }
    }

    AddComponent(DetectorComponent* component)
    {
        fComponents.push_back(component);
    }
protected:
    G4VPhysicalVolume* ConstructWorldVolume() = 0;

private:
    G4VPhysicalVolume* fPhysicalWorld;
    std::vector<DetectorComponent*> fComponents;
}
```



## Putting it all together

Now we have the two basic universal ingredients ready and
we can use them to put together real components.
We create a composite detector construction class - let's call it `MyGeometry` - and two
component classes - named `Component1` and `Component2` for
simplicity.

I won't add any detailed code, just the basic idea:

```c++
class Component1 : public DetectorComponent
{
public:
    const Component1() : DetectorComponent("component1") { }

    G4LogicalVolume* Construct() {
        ...     // Add some real code here
    }
}

class Component2 : public DetectorComponent
{
    ... // Define this component in a similar way
}

class MyGeometry : public CompositeDetectorConstruction
{
public:
    MyGeometry()
    {
        auto component1 = new Component1();
        component1->SetPosition({1.0 * m, 1.0 * m, 0.0});
        AddComponent(component1);

        auto component2 = new Component2();
        component2->SetPosition({0.0, 0.0, 0.0})     // i.e. keep the default
        AddComponent(component2);
    }

    G4VPhysicalVolume* ConstructWorldVolume()
    {
        ... // Implement
    }
}

// ...and obviously in the right place:
G4RunManager::GetRunManager()->SetUserInitialization(new MyGeometry());
```

Now our composite geometry is complete. The code for both components
is as independent as reasonably achievable and we can manipulate
any of them without feeling afraid of destroying the other one.

I hope you will like this concept and that maybe you will use it in
your own applications.

## P.S. What is missing?

Naturally, there are a few issues that I did not discuss in this post - be
it on purpose or because of my ignorance. The full implementation of both
fundamental classes is very simple and contains only the necessary
functionality because my intention was to show the design principle,
not to provide a full library. Some of the issues that may show up are
easy to deal with, some less so.

Among other details, I did not deal with:

* **rotations**;

* **parallel worlds**;

* **hierarchy of components**;

* **multiple copies of a single component**;

* **component destructors and memory management** - this is always difficult in Geant4 and its non-uniform pointer policies;

* **UI messengers**;

* **Geant4 state machine checks** - we should limit all component
state changes to PreInit phase unless we are very very careful about
the consequences.

Perhaps, in a later post, I will further developed the ideas
and take care of the "forgotten issues".

## Disclaimer

This post is based on the work I have done for the ELIMED project
(closed-source) and also on my library g4application (open-source, see <https://github.com/janpipek/g4application>) -
both projects employ a variant of the presented concept.
