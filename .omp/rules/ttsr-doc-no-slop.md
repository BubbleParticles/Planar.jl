---
name: ttsr-doc-no-slop
description: "Write docs in direct engineering style: no marketing voice, no cheesy headers, minimal words"
condition: "(?:\\bWelcome to\\b|\\bLet'?s dive (?:in|into)\\b|\\bIn this guide,? you'?ll\\b|\\bWhether you'?re\\b|\\bwe'?ll (?:walk|explore|cover|look at)\\b|\\bDive into\\b|\\bto the next level\\b|\\bUnlock the\\b|\\bEmpower\\b|\\bSeamless(?:ly)?\\b|\\bEffortless(?:ly)?\\b|\\bsupercharge\\b|\\Brocks?tars?\\b|\\bpowerhouse\\b|By the end of this (?:guide|section)\\b)"
scope: "text"
---

Write documentation in a dry, direct engineering style: state what the section covers, then the content. No marketing voice, no promotional adjectives (seamless, effortless, unlock, supercharge, robust, powerful, game-changer), no cheesy framing ('Welcome to _', "Let's dive into _", 'In this guide you'll learn', 'By the end of this guide you'll be able to'). Use plain noun or verb-phrase headings ('Data Pipeline', not 'The Power of Data Pipelines' and never 'X: The Y of Z'). Minimize words: drop any sentence the reader could skip, prefer terse concrete statements over filler. Fewer words, more signal.