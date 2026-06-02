import json

threads = [
{"threadId": "14e83f21935535a7", "messages": [
{"messageId": "14e83f21935535a7", "headers": {"From": "Benjamin Menkuec <benjamin.menkuec@googlemail.com>", "Date": "Sun, 12 Jul 2015 13:25:55 -0700", "Subject": "[opencog-dev] Interfacing DeSTIN to OpenCOG"}, "body": "I thought about the interface of DeSTIN and OpenCog. My favorite theory how this linking is done biologically is consciousness being different parts of the brain synchronized through long axon fibers. I think there would be a multidimensional fingerprint of high and low-level features that could be linked directly to atoms."},
{"messageId": "14e858f9a4bbcd6f", "headers": {"From": "Ben Goertzel <ben@goertzel.org>", "Date": "Sun, 12 Jul 2015 23:57:36 -0400", "Subject": "Re: [opencog-dev] Interfacing DeSTIN to OpenCOG"}, "body": "This makes sense conceptually. The challenge at the moment is getting the intermediate and upper layers of DeSTIN to have nodes with meaningful patterns in them, which are worth feeding into OpenCog. We are currently looking at hybrid architectures combining aspects of DeSTIN with aspects of denoising stacked autoencoders or convolutional autoencoders."},
{"messageId": "14e86b9506e13448", "headers": {"From": "Benjamin Menkuec <benjamin.menkuec@googlemail.com>", "Date": "Mon, 13 Jul 2015 02:22:45 -0700", "Subject": "Re: [opencog-dev] Interfacing DeSTIN to OpenCOG"}, "body": "I think cognitive synergy is very important when training the vision network, because biologically most of the training is done supervised through other cognitive modalities. A joint training of more than one modality would be a good idea, most practicably vision + language."},
{"messageId": "14e86bee9052cb1c", "headers": {"From": "Ben Goertzel <ben@goertzel.org>", "Date": "Mon, 13 Jul 2015 05:28:52 -0400", "Subject": "Re: [opencog-dev] Interfacing DeSTIN to OpenCOG"}, "body": "Actually what I am thinking about now is related but not the same as the wiki page, see attached StackedSemilocalizedAutoencoders.pdf."},
{"messageId": "14e86c06490cd83f", "headers": {"From": "Ben Goertzel <ben@goertzel.org>", "Date": "Mon, 13 Jul 2015 05:30:29 -0400", "Subject": "Re: [opencog-dev] Interfacing DeSTIN to OpenCOG"}, "body": "I agree that cross-modal information will be very important for AGI vision processing. However, I also think one can make a first-pass vision-cognition interface without it. It will just make dumb mistakes sometimes, when cross-modal information would help it."},
{"messageId": "14e86d0beb6aadb7", "headers": {"From": "Benjamin Menkuec <benjamin.menkuec@googlemail.com>", "Date": "Mon, 13 Jul 2015 02:48:21 -0700", "Subject": "Re: [opencog-dev] Interfacing DeSTIN to OpenCOG"}, "body": "I think the cross-modal information has 2 purposes: 1. supervised training, 2. assisting the recognition process. For purpose 2 it would be dispensable and just lead to some stupid errors. For 1 I am not so sure."}
]}
]

for t in threads:
    with open("raw_data_exports/gmail_raw_2015/" + t["threadId"] + ".json", "w") as f:
        json.dump(t, f, indent=2)
    print("Saved " + t["threadId"])
