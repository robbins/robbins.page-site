+++
title="Walnut, a course scheduler app for Android"
description="Walnut is a course scheduling app built for the Software Design class at UofT. It includes an intuitive & easy-to-use UI following Google's Material Design 3, single activity architechture, and modern Android Architechture Components, like Google's own Navigation framework. Work was completed in teams of 5 following the Scrum framework."
date = 2023-01-21
+++
For the final project in my Software Design course, I worked in a group of 5 following the Scrum framework to create a course scheduler app students & administration. The login & signup was implemented using Firebase Authentication, and the courses are stored in a Firebase Realtime Database. The UI follows modern Android development principles like the single-activity architechture, and Google's Navigation component. The UI also follows Google's Material Design 3 library. The login and signup components follow the Model-View-Presenter pattern, and unit testing of these components uses Mockito. Due to following the MVP design pattern, the Java components can be tested independently of the Android components.


## Features
* Course timeline generator that accounts for prerequisites
* Admin pages to add and remove courses, and set offering sessions and prerequisites.
* Email & password signup/login
* Saving taken courses
* Selecting courses you wish to take

## Screenshots
{{ gallery() }}
