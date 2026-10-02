# allpcc exploration

This branch starts from `pcc-full` and removes the local metadata-analysis pass.

## Architecture

1. **Local macOS boundary**
   - obtains the user-selected security-scoped folder
   - enumerates file URLs and assigns opaque UUIDs
   - does **not** collect size, creation/modification/access dates, UTI, hashes, image dimensions, or feature vectors for AI reasoning

2. **Private Cloud Compute**
   - profiles file content and assigns `FileType`
   - compares image attachments directly for visual duplicate identity
   - compares PCC-generated content profiles for non-image duplicates
   - selects canonical duplicate keepers
   - decides `keep`, `trash`, `move`, or `review` within the local safety policy
   - generates the cleanup plan

3. **Human approval + local execution**
   - no filesystem mutation happens during PCC analysis
   - the cleanup plan is shown in the existing review UI
   - only user-approved actions are executed locally

## Foundation Models 27 attachment boundary

Foundation Models 27 provides first-class image attachments, including image file URLs. It does not currently provide a generic arbitrary-file URL attachment for PDF, text, archive, or other binary files.

Because of that platform boundary:
- images are sent directly as PCC image attachments
- text is transported as raw text to PCC without a metadata pre-pass
- PDF text is mechanically extracted only as a transport bridge, then PCC performs the semantic interpretation
- unsupported binary formats use a bounded raw-byte sample and conservative PCC reasoning

So `allpcc` removes local metadata-based AI decisions, but macOS still has to provide filesystem access and transport non-image content into the Foundation Models session.
