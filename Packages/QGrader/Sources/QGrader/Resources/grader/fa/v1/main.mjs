// The module's JS entry point (WasmMainJSPath). The .NET WASM SDK requires
// one, and it is also the reference for how a client is meant to load this
// grader -- there is no client in this repo, so this file is the closest thing
// to documentation of the calling convention that actually executes.
//
// Nothing here is Qamooscheh-specific beyond the two export names. A real
// client would inline this loading step into its own bootstrap rather than
// shipping this file, but the shape does not change.

import { dotnet } from './_framework/dotnet.js';

const { getAssemblyExports, getConfig } = await dotnet.create();
const exports = await getAssemblyExports(getConfig().mainAssemblyName);

/**
 * The grader, as a plain JS object. Both calls return a JSON string holding a
 * GraderResponse: { verdict, matchedAnswer, correct, acceptedWithCorrection,
 * reasons[], error? }.
 *
 * `error` is set only for a request the grader could not interpret. A wrong
 * answer is a successful call with verdict "Incorrect" -- a client that treats
 * those two the same will silently stop grading offline the moment it sends a
 * typo'd exercise type.
 */
export const grader = {
    grade: (exerciseType, scriptMode, submitted, acceptedAnswers) =>
        JSON.parse(exports.Qamooscheh.Persian.Grader.Browser.GraderExports.Grade(
            exerciseType, scriptMode, submitted, JSON.stringify(acceptedAnswers))),

    gradeEnvelope: (request) =>
        JSON.parse(exports.Qamooscheh.Persian.Grader.Browser.GraderExports.GradeEnvelope(
            JSON.stringify(request))),
};

export default grader;
