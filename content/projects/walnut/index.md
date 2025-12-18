+++
title = "Walnut"
description = "A course scheduler app for Android with a modern UI following Material Design 3."
date = "2024-09-12"
template = "post.html"
+++

[Walnut](http://github.com/b07boys/walnut) is a course scheduling app built for CSCB07, the Software Design course at UTSC, in a team of 5.

# Features
- Course timeline generator that accounts for prerequisites
- Admin pages to add and remove courses, and set offering sessions and prerequisites.
- Email & password signup/login
- Saving taken courses
- Selecting courses you wish to take

# Architecture
While we didn't get to explore Jetpack Compose and all the niceties Kotlin has to offer, it tries to follow (as best as possible) modern Android app development guidelines under the project constraints of Java, XML, and the Model-View-Presenter pattern.

The UI is built using Google's Material Design 3 components which is an easy way to get a simple, good-looking interface (while also supporting Material You!).

In terms of app architecture, it follows the recommended single-activity pattern, 
and uses other Jetpack components such as Jetpack Navigation. The login and signup flows
follow the MVI architecture in combination with Mockito for JVM-only unit-testing. While my opinion of mock testing
has soured as I've gained more experience, it seemed to work fairly well for the limited scope and testing we did for this project.

The database used was also a less-complicated option, going with Firebase's Realtime Database to store user logins and course information.
