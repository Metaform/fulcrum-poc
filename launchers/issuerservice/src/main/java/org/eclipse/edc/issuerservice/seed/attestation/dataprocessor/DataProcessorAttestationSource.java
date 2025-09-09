/*
 *  Copyright (c) 2025 Metaform Systems, Inc.
 *
 *  This program and the accompanying materials are made available under the
 *  terms of the Apache License, Version 2.0 which is available at
 *  https://www.apache.org/licenses/LICENSE-2.0
 *
 *  SPDX-License-Identifier: Apache-2.0
 *
 *  Contributors:
 *       Metaform Systems, Inc. - initial API and implementation
 *
 */

package org.eclipse.edc.issuerservice.seed.attestation.dataprocessor;

import org.eclipse.edc.issuerservice.spi.issuance.attestation.AttestationContext;
import org.eclipse.edc.issuerservice.spi.issuance.attestation.AttestationSource;
import org.eclipse.edc.spi.result.Result;

import java.util.Map;

public record DataProcessorAttestationSource(Map<String, Object> config) implements AttestationSource {
    private static final String DEFAULT_CONTRACT_VERSION = "1.0.0";
    private static final String LEVEL = "processing";

    @Override
    public Result<Map<String, Object>> execute(AttestationContext context) {
        var contractVersion = config.getOrDefault("contractVersion", DEFAULT_CONTRACT_VERSION);
        return Result.success(Map.of(
                "contractVersion", contractVersion,
                "level", LEVEL,
                "id", context.participantId()
        ));
    }
}
