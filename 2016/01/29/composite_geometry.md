Title: Build your Geant4 detector construction from independent components
Tags: geometry
    geant4
    composite

In Geant4, you are supposed to develop a single class responsible
for the whole detector construction (a.k.a. geometry); it has to inherit from
`G4VUserDetectorConstruction` and everything should happen or at
least should be initiated from its `Construct` and possibly
`ConstructSDandField` methods.

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
A component is a class which describes, as independently of the rest
of the application as possible, a single part of the geometry.

The whole design then follows these guidelines:

* All components must derive from a common class, `GeometryComponent`, that
contains shared functionality (which is not very wide).

* The mechanism for combining components should be implemented
in a general class that does not involve any concrete geometry. Let's call
it `CompositeDetectorConstruction`. This class could be included
in whatever application without a change.

* In a specific detector construction class of the application,
each component should be just instantiated and perhaps positioned
(both in one place).

...UML diagram

## The GeometryComponent class

What should a component do? In a way, it is a mini-detector construction in itself.
So, we should definitely define `Construct` and `ConstructSDandField` methods for it.
Following the detector construction, `Construct` is pure virtual (abstract) and you have
to override it, `ConstructSDandField` has a default (trivial) implementation.

Be aware, that the signature of `Construct` is different from detector construction!
The component won't be able for creating its physical volume and therefore
it returns a logical volume instead of physical volume.

We will just keep the name, position (and potentially rotation,
which we won't deal with for simplicity) as data members (with setters and getters).

This leaves the class definition (not split into header+source files) quite simple:

```c++
class GeometryComponent
{
public:
    GeometryComponent(G4String& name)
        : fName(name), fEnabled(true), fPosition({0.0, 0.0, 0.0}) { }
    virtual ~GeometryComponent() = default;

    virtual G4LogicalVolume* Construct() = 0;    // overriding compulsary
    virtual void ConstructSDandField() { }       // default implementation

    const G4String& GetName() const { return fName; }

    const G4ThreeVector& GetPosition() const { return fPosition; }
    void SetPosition(const G4ThreeVector& pos) { fPosition = pos; }

    G4bool IsEnabled() const { return fEnabled; }
    void SetEnabled(G4bool enabled) { fEnabled = enabled; }

private:
    G4String fName;
    G4bool fEnabled;
    G4ThreeVector fPosition;    
}
```

For simplicity, I don't define a *messenger* for the class (it is a trivial step)
or deal with the possibility of a component becoming a *sub-component* of another volume
(this is also possible but I do not want to complicated this text too much). Nor
do I add the above mentioned *rotation* which can be handled in a way similar to
position (there is a couple of caveats though).

## The CompositeGeometry class

This class is meant to be abstract although

(please, forgive my C++11)

```c++
class CompositeGeometry : public G4VUserDetectorConstruction
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
                fPhysicalWorld->GetLogicalVolume(),   // CHECK!!!
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

    AddComponent(GeometryComponent* component)
    {
        fComponents.push_back(component);
    }

private:
    G4VPhysicalVolume* fPhysicalWorld;
    std::vector<GeometryComponent*> fComponents;
}
```

## Putting it all together

Now we have the two basic universal ingredients ready and we can use them
to put together real components. Without

```c++
class Component1 : public GeometryComponent
{
public:
    const Component1() : GeometryComponent("component1") { }

    G4LogicalVolume* Construct() {
        ...     // Add some real code here
    }
}

class Component2 : public GeometryComponent
{
    ...

    // Define this component in a similar way
}
```

```c++
class ExampleGeometry : public CompositeGeometry
{
public:
    ExampleGeometry()
    {
        auto component1 = new Component1();
        component1->SetPosition({1.0 * m, 1.0 * m, 0.0});
        AddComponent(component1);

        auto component2 = new Component2();
        component2->SetPosition({0.0, 0.0, 0.0})     // i.e. keep the default
        AddComponent(component2);
    }
}
```

## Drawbacks

* parallel worlds
* multiple copies of a component
* deletion

## Conclusion

Perhaps, in a later post, I will enhance the `GeometryComponent class`.

## Disclaimer

This post is based on the work I have done for the ELIMED project (closed-source) and also on my
library g4application (open-source).
