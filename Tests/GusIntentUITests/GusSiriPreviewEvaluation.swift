#if GUS_SIRI_AI_PREVIEW && os(iOS) && !targetEnvironment(simulator) && canImport(SiriEvaluations)
    import SiriEvaluations
    import Testing

    private struct GusVoiceEvaluation: Evaluation {
        let name = "Gus library and downloads"
        let dataset = SiriScenarioLoader {
            SiriScenario {
                UserTurn("In Gus, open my downloads.") {
                    Calls { IntentDefinitions(bundleIdentifier: "dev.ericslutz.gus").intents["OpenDownloadsIntent"] }
                }
            }
            SiriScenario {
                UserTurn("In Gus, find the library title Northbound Example.") {
                    Calls {
                        IntentDefinitions(bundleIdentifier: "dev.ericslutz.gus").intents["FindLibraryItemsIntent"]
                            .expect(search: .equals("Northbound Example"))
                    }
                }
            }
        }

        var evaluators: Evaluators {
            SiriExpectationEvaluator()
        }

        func subject(from sample: SiriScenario) async throws -> SiriScenarioSubject {
            try await SiriService.run(scenario: sample)
        }

        func aggregateMetrics(using aggregator: inout MetricsAggregator) {
            Self.computeSiriMetrics(into: &aggregator)
        }
    }

    @Test(.evaluates(GusVoiceEvaluation()))
    private func routesGusVoiceRequests() {
        #expect(EvaluationContext.current.result.aggregateValue(.mean(of: .intentsAllPass)) == 1)
    }
#endif
