// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
import { Stack, App, DefaultStackSynthesizer } from 'aws-cdk-lib';
import { StringParameter } from 'aws-cdk-lib/aws-ssm';
import { Template } from 'aws-cdk-lib/assertions';
import { PlaybookPrimaryStack, PlaybookMemberStack } from '../../../lib/playbook-construct';
import { omitWaitResourceHash } from '../../../test/utils';

const RESOURCE_PREFIX = 'SO0111';

function getPrimaryStack(): Stack {
  const app = new App();
  const stack = new PlaybookPrimaryStack(app, 'primaryStack', {
    synthesizer: new DefaultStackSynthesizer({ generateBootstrapVersionRule: false }),
    description: 'test;',
    solutionId: 'SO0111',
    solutionVersion: 'v1.1.1',
    solutionDistBucket: 'sharrbukkit',
    solutionDistName: 'automated-security-response-on-aws',
    remediations: [
      { control: '1.1', versionAdded: '2.1.0' },
      { control: '1.2', versionAdded: '2.2.0' },
      { control: '1.3', versionAdded: '2.1.1' },
    ],
    securityStandard: 'CIS',
    securityStandardLongName: 'cis-aws-foundations-benchmark',
    securityStandardVersion: '1.2.0',
  });
  return stack;
}

test('default stack', () => {
  const stack = getPrimaryStack();
  const template = Template.fromStack(stack);

  const templateJSON = template.toJSON();
  omitWaitResourceHash(template, templateJSON);
  expect(templateJSON).toMatchSnapshot();
});

function getMemberStack(): Stack {
  const app = new App();
  const stack = new PlaybookMemberStack(app, 'memberStack', {
    synthesizer: new DefaultStackSynthesizer({ generateBootstrapVersionRule: false }),
    description: 'test;',
    solutionId: 'SO0111',
    solutionVersion: 'v1.1.1',
    solutionDistBucket: 'sharrbukkit',
    securityStandard: 'CIS',
    securityStandardVersion: '1.2.0',
    securityStandardLongName: 'cis-aws-foundations-benchmark',
    ssmdocs: 'playbooks/CIS120/ssmdocs',
    commonScripts: 'playbooks/common',
    remediations: [
      { control: '1.3', versionAdded: '2.1.0' },
      { control: '1.5', versionAdded: '2.2.0' },
      { control: '2.1', versionAdded: '2.1.1' },
    ],
  });

  new StringParameter(stack, `Remap CIS 4.2`, {
    description: `Remap the CIS 4.2 finding to CIS 4.1 remediation`,
    parameterName: `/Solutions/${RESOURCE_PREFIX}/cis-aws-foundations-benchmark/1.2.0-4.2`,
    stringValue: '4.1',
  });
  return stack;
}

test('default stack', () => {
  const stack = getMemberStack();
  const template = Template.fromStack(stack);

  const templateJSON = template.toJSON();
  omitWaitResourceHash(template, templateJSON);
  expect(templateJSON).toMatchSnapshot();
});
