#!/usr/bin/env node
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
import { PlaybookMemberStack, PlaybookPrimaryStack } from '../../../lib/playbook-construct';
import * as cdk from 'aws-cdk-lib';
import 'source-map-support/register';
import { AFSBP_REMEDIATIONS } from '../lib/afsbp_remediations';
import { splitMemberStack } from '../../split_member_stacks';

// set by solution_env.sh
const SOLUTION_ID = process.env['SOLUTION_ID'] || 'undefined';
const SOLUTION_NAME = process.env['SOLUTION_NAME'] || 'undefined';
const MEMBER_STACK_LIMIT = process.env['AFSBP_MEMBER_STACK_LIMIT']
  ? Number(process.env['AFSBP_MEMBER_STACK_LIMIT'])
  : Infinity;
// DIST_* - set by build-s3-dist.sh
const DIST_VERSION = process.env['DIST_VERSION'] || '%%VERSION%%';
const DIST_OUTPUT_BUCKET = process.env['DIST_OUTPUT_BUCKET'] || '%%BUCKET%%';
const DIST_SOLUTION_NAME = process.env['DIST_SOLUTION_NAME'] || '%%SOLUTION%%';

const standardShortName = 'AFSBP';
const standardLongName = 'aws-foundational-security-best-practices';
const standardVersion = '1.0.0'; // DO NOT INCLUDE 'V'

const app = new cdk.App();

const adminStack = new PlaybookPrimaryStack(app, 'AFSBPStack', {
  analyticsReporting: false, // CDK::Metadata breaks StackSets in some regions
  synthesizer: new cdk.DefaultStackSynthesizer({ generateBootstrapVersionRule: false }),
  description: `(${SOLUTION_ID}P) ${SOLUTION_NAME} ${standardShortName} ${standardVersion} Compliance Pack - Admin Account, ${DIST_VERSION}`,
  solutionId: SOLUTION_ID,
  solutionVersion: DIST_VERSION,
  solutionDistBucket: DIST_OUTPUT_BUCKET,
  solutionDistName: DIST_SOLUTION_NAME,
  remediations: AFSBP_REMEDIATIONS,
  securityStandardLongName: standardLongName,
  securityStandard: standardShortName,
  securityStandardVersion: standardVersion,
});
adminStack.templateOptions.templateFormatVersion = '2010-09-09';

splitMemberStack({
  scope: app,
  stackClass: PlaybookMemberStack,
  stackLimit: MEMBER_STACK_LIMIT,
  remediations: AFSBP_REMEDIATIONS,
  baseStackName: 'AFSBPMemberStack',
  standardShortName: standardShortName,
  standardVersion: standardVersion,
  standardLongName: standardLongName,
});
