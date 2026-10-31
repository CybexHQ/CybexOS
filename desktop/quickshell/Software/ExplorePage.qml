pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers

// The front page: the apps doing each everyday job, which you can change,
// then everything to discover: featured apps, the eight categories,
// collections from the installer's profiles, and what people install most.
PageScroll {
    id: root

    readonly property var featured: Helpers.featured(Software.apps, Software.catalogue.featured || [])
    readonly property int popularColumns: Helpers.columns(innerWidth, Theme.scaled(220), Theme.scaled(10))

    objectName: "softwareExplorePage"
    spacing: Theme.scaled(12)

    DefaultsSection {
        width: parent.width
    }
    Rectangle {
        width: parent.width
        height: 1
        color: Theme.hairlineSoft
    }
    SectionTitle {
        width: parent.width
        text: I18n.tr("Discover")
        detail: I18n.tr("More apps, all prebuilt · nothing to compile")
    }

    HeroCarousel {
        objectName: "softwareHero"
        width: parent.width
        visible: root.featured.length > 0
        apps: root.featured
    }

    SectionTitle {
        width: parent.width
        text: I18n.tr("Categories")
    }
    Grid {
        id: categories
        width: parent.width
        columns: Math.min(4, Helpers.columns(width, Theme.scaled(190), Theme.scaled(10)))
        spacing: Theme.scaled(10)
        Repeater {
            model: Software.categories
            delegate: CategoryTile {
                required property var modelData
                objectName: "softwareCategory"
                width: (categories.width - categories.spacing * (categories.columns - 1)) / categories.columns
                category: modelData
            }
        }
    }

    SectionTitle {
        width: parent.width
        visible: Software.profiles.length > 0
        text: I18n.tr("Collections")
        detail: I18n.tr("Add a whole set at once")
    }
    Grid {
        id: collections
        width: parent.width
        visible: Software.profiles.length > 0
        columns: Math.min(3, Helpers.columns(width, Theme.scaled(260), Theme.scaled(10)))
        spacing: Theme.scaled(10)
        Repeater {
            model: Software.profiles
            delegate: CollectionCard {
                required property var modelData
                width: (collections.width - collections.spacing * (collections.columns - 1)) / collections.columns
                profile: modelData
            }
        }
    }

    SectionTitle {
        width: parent.width
        text: I18n.tr("Popular on Cybex OS")
        link: I18n.tr("See all")
        onLinkClicked: Software.openList("popular")
    }
    Grid {
        id: popular
        width: parent.width
        columns: Math.min(4, root.popularColumns)
        spacing: Theme.scaled(10)
        Repeater {
            model: Helpers.popular(Software.apps, popular.columns * 2)
            delegate: AppCard {
                required property var modelData
                objectName: "softwarePopularApp"
                width: (popular.width - popular.spacing * (popular.columns - 1)) / popular.columns
                app: modelData
            }
        }
    }
}
