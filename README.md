# Proof-of-Concept Fulcrum + EDC

<!-- TOC -->

* [Proof-of-Concept Fulcrum + EDC](#proof-of-concept-fulcrum--edc)
    * [1. Introduction](#1-introduction)
    * [2. Definition of terms](#2-definition-of-terms)
    * [3. Prerequisites and requirements](#3-prerequisites-and-requirements)
        * [3.1 Prerequisites](#31-prerequisites)
        * [3.2 Kubernetes network requirements](#32-kubernetes-network-requirements)
    * [4. Getting started](#4-getting-started)
        * [4.1 Deploy base infrastructure](#41-deploy-base-infrastructure)
        * [4.2 Inspect IP addresses and IDs](#42-inspect-ip-addresses-and-ids)
        * [4.3 Seeding initial data](#43-seeding-initial-data)
        * [4.4 Create participants](#44-create-participants)
        * [4.5 Delete a participant](#45-delete-a-participant)
        * [4.6 Requesting a credential](#46-requesting-a-credential)
        * [4.7 Exchange data](#47-exchange-data)
    * [5. Components and setup](#5-components-and-setup)
        * [5.1 Base infrastructure](#51-base-infrastructure)
            * [5.1.1 IssuerService](#511-issuerservice)
            * [5.1.2 Provisioner agent](#512-provisioner-agent)
            * [5.1.3 Credential types](#513-credential-types)
        * [5.2 Participant infrastructure](#52-participant-infrastructure)
    * [6. References](#6-references)

<!-- TOC -->

## 1. Introduction

This Proof-of-Concept (PoC) demonstrates how to onboard participants into a dataspace based on Eclipse Dataspace
Components using Fulcrum Core. It implements the following main
features:

- deploying base infrastructure, consisting of an IssuerService and a Provisioner agent
- onboarding participants by deploying a dedicated IdentityHub, Control Plane, and Data Plane for each participant
- requesting verifiable credentials from the IssuerService by using the IdentityHub's Identity API

To keep things simple, all resources are deployed on a single Kubernetes cluster.

## 2. Definition of terms

- _user_: a person interacting with various APIs that one particular _participant_ exposes
- _base infrastructure_: the IssuerService and the Provisioner agent, which are deployed once per data space
- _participant_: a participating entity in a dataspace, e.g. a company or an organization. This is NOT a human being,
  but rather a legal entity.
- _participantContext_: technically, IdentityHub is multi-tenant, so it could handle multiple participants in one
  instance. In this PoC, however, each
  participant gets its own IdentityHub instance, so there is only one participantContext per IdentityHub. A
  _participantContext_ is identified by its
  _participantContextId_, which - for this PoC - is identical to the participant's DID.
- _verifiable credential_: a structured, cryptographically verifiable claim about a _participant_ that is issued by an
  _issuer_ and held by a _holder_. A VC is
  a JSON document, secured by a proof, e.g. a digital signature.
- _issuer_: an entity that issues verifiable credentials to participants. In this PoC, the IssuerService is the issuer.
  An issuer must be trusted by the
  participants.
- _holder_: an entity that holds verifiable credentials. In this PoC, the IdentityHub acts as the holder.

## 3. Prerequisites and requirements

### 3.1 Prerequisites

To deploy the base components of this PoC, the following things are required:

- a fresh Kubernetes cluster
- NGINX ingress controller installed, e.g. by running:

  ```shell
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.0/deploy/static/provider/cloud/deploy.yaml
  ```

- `kubectl` installed on dev machine
- either Terraform or OpenTofu (recommended) installed on the dev machine
- a GitHub account and a PAT (needed to [authenticate to
  GHCR](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-to-the-container-registry))
- a POSIX-compliant shell
- this repository cloned locally
- Windows _might_ be supported as base OS, but paths may need to be adapted. We've only tested on macOS.

_All shell commands are assumed to be executed from the repository root unless stated otherwise._

### 3.2 Kubernetes network requirements

Some services in this PoC use an NGINX ingress controller to route HTTP requests to all the individual services and
make them accessible from outside the cluster.

On local Kubernetes development installations, for example, Proxmox VMs or bare metal, the Ingress Controller service
and LoadBalancers won't automatically get
an external IP (`ClusterIP` will only be reachable from inside the cluster), so we need another service to do that.
MetalLB is a load-balancer implementation for bare metal Kubernetes clusters, which works well for this purpose. Please
follow the instructions on the [MetalLB
installation page](https://metallb.universe.tf/installation/) to install it on your cluster.

MetalLB needs an IP address pool to allocate external IPs from, at least 2 IP addresses are needed: one for the
IssuerService ingress controller, one for the
Fulcrum Core API loadbalancer service. This should be a range of IPs that are not used by other devices on your network.
Whichever IP MetalLB assigns to the
Ingress Controller, you will use that IP ("kubeHost" or "Kubernetes external IP") to access the APIs of the
IssuerService and the provisioner.

Note that most cloud providers assign an external IP to the cluster, so MetalLB is not needed there.

Note also that on KinD, the situation is slightly different: there is a
special [installation procedure](https://kind.sigs.k8s.io/docs/user/ingress) when using
NGINX ingress with KinD.

## 4. Getting started

### 4.1 Deploy base infrastructure

To install the base components (IssuerService and Provisioner agent) on the cluster, please run

```shell
GH_PAT=ghp_...
GH_USERNAME=...
tofu -chdir=deployment init # only needed once
tofu -chdir=deployment apply -var ghcr_pat=$GH_PAT -var ghcr_username=$GH_USERNAME
```

And confirm by typing `yes`. After Terraform has completed, inspect the pods by typing `kubectl get pods -n poc-issuer`
and `kubectl get pods -n fulcrum-core`. The output should be similar to this:

```shell
NAME                                        READY   STATUS    RESTARTS   AGE
dataspace-issuer-service-5d68c4cdf8-4cmx4   1/1     Running   0          56s
issuer-postgres-6cfc666468-srsp4            1/1     Running   0          58s
issuer-vault-0                              1/1     Running   0          55s
```

and

```shell
NAME                           READY   STATUS    RESTARTS      AGE
core-api-66c57cf4d8-vnf5f      1/1     Running   0             34s
postgres-65dbd7f5-gnphm        1/1     Running   0             34s
provisioner-5c77f4f889-gm7dh   1/1     Running   1 (31s ago)   34s
```

Note that according to documentation, OpenTofu/Terraform _should_ respect the `$KUBECONFIG` variable, but that doesn't
seem to be the case in all instances.
Therefor, the Terraform scripts reference `~/.kube/config` directly. If your kubeconfig is located somewhere else,
please run `ln -sf <your-kubeconfig>
~/.kube/config`.

**This overwrites the existing `~/.kube/config` file, so make a backup if needed.**

### 4.2 Inspect IP addresses and IDs

Note that the IP address of the provisioner service will likely be different from the IP address of the Fulcrum Core
API.
This will largely depend on your local Kubernetes cluster setup: on cloud-based installations this
might be a DNS-resolvable host name, on bare metal those IPs depend on the settings of the load balancer (we're using
MetalLB) and on the assigned IP Pool.

The easiest way to inspect that is to run `kubectl get services -A` which will display something like this:

```text
NAMESPACE        NAME                                                 TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)
default          kubernetes                                           ClusterIP      10.96.0.1        <none>          443/TCP
fulcrum-core     core-api-lb                                          LoadBalancer   10.100.70.10     192.168.1.202   3000:30888/TCP
fulcrum-core     postgres                                             NodePort       10.108.39.149    <none>          5432:31622/TCP
fulcrum-core     provisioner-service                                  ClusterIP      10.98.253.109    <none>          9999/TCP
ingress-nginx    ingress-nginx-controller                             LoadBalancer   10.111.15.99     192.168.1.201   80:31252/TCP,443:30834/TCP
```

The `EXTERNAL-IP` column should contain the IP addresses of the Ingress Controller (`192.168.1.201`), which is used by
all EDC-based services, such as IdentityHub, Control Plane, etc. In the next step, we'll use it for the `kubeHost`
property. It should also contain an IP address for the `core-api-lb` service (`192.168.1.202`), which is used as the
Fulcrum Core API host.

For this PoC, the DID is constructed as follows:

### 4.3 Seeding initial data

The IssuerService requires some initial data which we'll insert by executing the seed script. In the following example,
the IP address of the ingress controller
for all EDC services is `192.168.1.201`, please substitute it to fit your local setup:

```shell
./seed-k8s.sh --host 192.168.1.201
```

Executing this script repeatedly will log an error ("ObjectConflict"), but that is OK. It should produce an output
similar to this:

```text
Seeding data to ingress host 192.168.1.201

Create dataspace issuer
{"apiKey":"ZGlkOndlYjpkYXRhc3BhY2UtaXNzdWVyLXNlcnZpY2UucG9jLWlzc3Vlci5zdmMuY2x1c3Rlci5sb2NhbCUzQTEwMDE2Omlzc3Vlcg==.67AUWcBwiT11c/pUTyPKBOvNgyd/0n6vshttQksILmqgZN1WZw8i50Ww4D2Fc3+3kNpDJSFNc5ZL1NJOb+CqTA==","clientId":"did:web:dataspace-issuer-service.poc-issuer.svc.cluster.local%3A10016:issuer","clientSecret":"Jl5aAhoNlYANn5HA"}

Create attestation definition (membership)

Create attestation definition (dataprocessor)

Create credential definition (membership)

Create credential definition (dataprocessor)
```

### 4.4 Create participants

Onboarding a participant can be done using Fulcrum Core's REST API. In Fulcrum terminology, we are creating a _Service_,
which is the all-in-one deployment of participant resources. To do that, we require knowledge of the `serviceTypeId`,
the, and the `agentId`.

There are several ways to collect this information:

1. Upon startup, the provisioner will print this information. It can be observed on the provisioner pod's output:

   ```shell
   kubectl logs deployments/provisioner -n fulcrum-core
   ```

   ```json
   {
     "AgentId": "79939526-c6c8-4db5-a017-b96c86d3186f",
     "ProviderId": "4bf2a6bc-ca85-4ab7-a56b-6d0c0a4330f1",
     "AgentTypeId": "a84f88dd-8e5a-4dd0-a43b-d8651e088cab",
     "Name": "EDC Provisioner Agent",
     "ServiceTypeId": "655739f1-94ff-482a-b35c-3d50a08bc6e2",
     "ServiceGroupId": "32d05133-6456-42e7-8de6-cfa0ccb5e52f"
   }
   ```

2. use the [Fulcrum Core API](https://github.com/fulcrumproject/core/blob/main/docs/openapi.yaml). This might involve
   several API calls and may not be the
   quickest way.
3. inspect the Fulcrum Core API database by connecting to the database pod with your favorite PG viewer. Port-forwards
   will be needed - not elegant, but
   possible.

Using the Fulcrum Core API, we can create a _Service_ by executing

```shell
SERVICE_ID=$(curl --location 'http://192.168.1.202:3000/api/v1/services' \
--header 'Content-Type: application/json' \
--header 'Accept: application/json' \
--header 'Authorization: Bearer <TOKEN>' \
--data '{
  "name": "EDC Deployment Opiquad-04",
  "serviceTypeId": "655739f1-94ff-482a-b35c-3d50a08bc6e2",
  "groupId": "32d05133-6456-42e7-8de6-cfa0ccb5e52f",
  "properties": {
    "participantName": "opiquad04",
    "participantDid": "did:web:identityhub.opiquad04.svc.cluster.local%3A7083:opiquad04",
    "kubeHost": "192.168.1.201"
  },
  "agentTags": [
    "cfm", "edc"
  ],
  "agentId": "79939526-c6c8-4db5-a017-b96c86d3186f"
}' | jq -r ' .id ')
```

This _Service_ will contain vital information for the provisioner in the `properties` object, namely the
`participantName`, the `participantDid`, and the
`kubeHost`. The provisioner polls the Fulcrum Core API and picks up the resulting Fulcrum _Job_. The _Job_ is claimed,
resources are provisioned, and after
that, the _Job_ is marked as _completed_ in Fulcrum Core.

> We need to store the `SERVICE_ID` for later use, e.g. deleting the service.

Sometimes, the provisioner logs a warning indicating an HTTP 503 error. This happens when the provisioner attempts to
insert basic operational data into the newly created participant, before all Kubernetes services are 100% up and
running. In that case, simply re-run the `curl` command.

### 4.5 Delete a participant

Resources can be deleted by sending a DELETE request to Fulcrum:

```shell
curl --location --request DELETE "http://192.168.1.202:3000/api/v1/services/$SERVICE_ID" \
--header 'Accept: application/json' \
--header 'Authorization: Bearer <TOKEN>'
```

This is an asynchronous operation, so the provisioner will respond immediately with HTTP 20x. The actual deletion
progress can be observed by inspecting the
pods in the participant's namespace, e.g. by executing `kubectl get pods -n opiquad044 -w` until all pods are gone.

### 4.6 Requesting a credential

After the participant has been created, it can request verifiable credentials from the IssuerService. For this, we use
the participant's "Identity API" to talk
to the participant's IdentitHub, which is basically the management API of the IdentityHub. Again, assuming
`"192.168.1.201"` as the cluster external IP, we can
request credentials by executing

```shell
curl --location 'http://192.168.1.201/opiquad04/cs/api/identity/v1alpha/participants/ZGlkOndlYjppZGVudGl0eWh1Yi5vcGlxdWFkMDQuc3ZjLmNsdXN0ZXIubG9jYWwlM0E3MDgzOm9waXF1YWQwNA==/credentials/request' \
--header 'Content-Type: application/json' \
--header 'X-Api-Key: c3VwZXItdXNlcg==.c3VwZXItc2VjcmV0LWtleQo=' \
--data '{
    "issuerDid": "did:web:dataspace-issuer-service.poc-issuer.svc.cluster.local%3A10016:issuer",
    "holderPid": "credential-request-1",
    "credentials": [{
        "format": "VC1_0_JWT",
        "type": "MembershipCredential",
        "id": "membership-credential-def"
    },
    {
        "format": "VC1_0_JWT",
        "type": "DataProcessorCredential",
        "id": "dataprocessor-credential-def"
    }]
}'
```

Key elements to note here are:

- the URL contains the base64-encoded identifier of the participant, which should be identical to the participant's DID
  (`"did:web:identityhub.opiquad04.svc.cluster.local:7083:opiquad04"`)
- the `issuerDid` determines, where to send the issuance request. Technically, in a dataspace, there could be multiple
  issuers, so we need to specify which one
  to use.
- the `holderPid` is an arbitrary ID that can be chosen by the (prospective "holder" of the credential)
- each object in the `credentials` array determines, which credential is to be requested. This information is available
  via the issuer's [Metadata
  API](https://eclipse-dataspace-dcp.github.io/decentralized-claims-protocol/v1.0-RC4/#issuer-metadata-api), and here,
  we're requesting two credentials at once.
  Note that it is also possible to make two individual requests, but the `holderPid` then has to be different each time.
  The `type`, `format` and `id` must match the
  credential definitions that the IssuerService knows about. We created this data in
  step [4.3](#43-seeding-initial-data).

Credential issuance is also an asynchronous process, so the request immediately returns with HTTP 201. After a while,
the IdentityHub's logs should display
something similar to:

```text
identityhub DEBUG 2025-08-26T06:42:38.697336738 [CredentialRequestManagerImpl] HolderCredentialRequest credential-request-1 is now in state CREATED
identityhub DEBUG 2025-08-26T06:42:39.493424722 Processing 'CREATED' request 'credential-request-1'
identityhub DEBUG 2025-08-26T06:42:39.495968114 [CredentialRequestManagerImpl] HolderCredentialRequest credential-request-1 is now in state REQUESTING
identityhub DEBUG 2025-08-26T06:42:39.915779975 [CredentialRequestManagerImpl] HolderCredentialRequest credential-request-1 is now in state REQUESTED
identityhub DEBUG 2025-08-26T06:42:41.205526897 [StorageAPI] HolderCredentialRequest credential-request-1 is now in state ISSUED
```

From that point forward, the `MembershipCredential` and the `DataProcessorCredential` are held by our participant
"opiquad04" and can be used for presentation.

### 4.7 Exchange data

Now this is the big one: let’s provision two participants: one consumer and one provider. To do that, we need to call
the Fulcrum Core API (see [section 4.4](#44-create-participants))
and create two participants

First we create the consumer, called `opiquadc`:

```shell
SERVICE_ID=$(curl --fail --location 'http://localhost:3000/api/v1/services' \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json' \
  --header 'Authorization: Bearer change-me' \
  --data '{
    "name": "EDC Deployment Consumer Company (opiquadc)",
    "serviceTypeId": "b7d41935-7f39-47b0-9a57-fe198d1af317",
    "groupId": "803fd64c-c761-4cdf-8b6e-535f5f1473f7",
    "properties": {
      "participantName": "opiquadc",
      "participantDid": "did:web:identityhub.opiquadc.svc.cluster.local%3A7083:opiquadc",
      "kubeHost": "192.168.1.201"
  },
  "agentTags": [
    "cfm", "edc"
  ],
  "agentId": "e341ae76-815a-4d22-9305-5e799dccbe09"
  }' | jq '.id')
```

> **Important: let the entire deployment finish and settle down before continuing. Inspect the provisioner pod logs for
that.**

next, we create the provider, called `opiquadp`:

```shell
SERVICE_ID2=$(curl --fail --location 'http://localhost:3000/api/v1/services' \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json' \
  --header 'Authorization: Bearer change-me' \
  --data '{
    "name": "EDC Deployment Consumer Company (opiquadp)",
    "serviceTypeId": "b7d41935-7f39-47b0-9a57-fe198d1af317",
    "groupId": "803fd64c-c761-4cdf-8b6e-535f5f1473f7",
    "properties": {
      "participantName": "opiquadp",
      "participantDid": "did:web:identityhub.opiquadp.svc.cluster.local%3A7083:opiquadp",
      "kubeHost": "192.168.1.201"
  },
  "agentTags": [
    "cfm", "edc"
  ],
  "agentId": "e341ae76-815a-4d22-9305-5e799dccbe09"
  }' | jq '.id')
```

Once both those deployments are up and running, we can request credentials for both participants,
see [section 4.6](#46-requesting-a-credential), and start the negotiation process. For that, import
the [Postman collection](./postman)
into Postman, or a similar tool, and execute the requests one after the other.

Before we can do that, though, we need to populate a few collection variables:

- `EDC_HOST`: should point to the IP address of the NGINX ingress controller, in the snippets above, that'd be
  `192.168.1.201`
- `CONSUMER`: should be `opiquadc`
- `CONSUMER_BASE64`: should be the base64 web DID of the consumer
  `ZGlkOndlYjppZGVudGl0eWh1Yi5vcGlxdWFkYy5zdmMuY2x1c3Rlci5sb2NhbCUzQTcwODM6b3BpcXVhZGM=`
- `PROVIDER`: should be `opiquadp`
- `PROVIDER_ID`: should be `did:web:identityhub.opiquadp.svc.cluster.local%3A7083:opiquadp`
- `PROVIDER_BASE64`: should be the base64-encoded `PROVIDER_ID`, i.e.
  `ZGlkOndlYjppZGVudGl0eWh1Yi5vcGlxdWFkcC5zdmMuY2x1c3Rlci5sb2NhbCUzQTcwODM6b3BpcXVhZHA=`

Note that there is no variable for `CONSUMER_ID` because we don't need it. Note also, that a few variables are as yet
empty. We will populate them as we go through the requests.

Now execute all requests in the collection:

![img.png](resources/img.png)

The `Get All Assets` and `Check all credentials` requests are not required, but are a good way to check that the
provisioning process has been successful. 

It should be enough to simply execute one request after another. A few things to note:

- poll the contract negotiations until the response contains a `"state": "FINALIZED"` entry
- then start the transfer, again, polling the transfer requests until the response contains the `"state": "STARTED"` field, 

Click through the rest of the requests, including `Download data from provider`. If everything worked, you should see a JSON response like this:
```json lines
[
  {
    "userId": 1,
    "id": 1,
    "title": "delectus aut autem",
    "completed": false
  },
  {
    "userId": 1,
    "id": 2,
    "title": "quis ut nam facilis et officia qui",
    "completed": false
  },
  //...
]
```

This means we've just downloaded data from the provider's data plane, using all of EDC's negotiation and transfer features!

### 4.7.1 Cleanup

To clean up the deployment, simply delete the services: 

```shell
curl --location --request DELETE http://localhost:3000/api/v1/services/$SERVICE_ID \
  --header 'Accept: application/json' \
  --header 'Authorization: Bearer <TOKEN>'
```
(do the same for `$SERVICE_ID2`)

## 5. Components and setup

The PoC consists of two main classes of components:

1. base infrastructure, consisting of Fulcrum Core, the IssuerService, and the provisioner agent
2. participant infrastructure, consists of the Identity Hub, the Control Plane and the Data Plane plus their
   dependencies (primarily PostgreSQL and Vault).

The following diagram illustrates the overall architecture:

![Architecture diagram](./docs/images/architecture.svg)

### 5.1 Base infrastructure

The base infrastructure (shown in orange and pink) is deployed once per cluster and consists of Fulcrum Core, the
IssuerService, and the Provisioner agent. This
is done by running the Terraform/OpenTofu scripts in the `deployment` folder,
see [section 3.3](#41-deploy-base-infrastructure) for details.

#### 5.1.1 IssuerService

This is a DCP-compliant issuer service that receives verifiable credential requests from participants and issues the
requested credentials. It is based on the
[reference implementation](https://github.com/eclipse-edc/IdentityHub/blob/main/docs/developer/architecture/issuer/issuance/issuance.process.md)
of the
[Decentralized Claims Protocol](https://eclipse-dataspace-dcp.github.io/decentralized-claims-protocol).

In short, the IssuerService uses so-called `CredentialDefinitions` to generate Verifiable Credentials for participants.
The data that is being written into the credentials comes from so-called `AttestationDefinitions` which are linked to
the `CredentialDefinitions`. For this PoC, the data is hardcoded for each credential type in the
IssuerService's [code base](./launchers/issuerservice/src/main/java/org/eclipse/edc/issuerservice/seed/attestation/),
but in a production scenario this data would likely come from an external source, e.g. a database or an API.

#### 5.1.2 Provisioner agent

The provisioner agent is responsible for deploying the participant infrastructure on behalf of an onboarding platform.
It exposes a REST API that can be used to request the provisioning and the de-provisioning of a new participant by
providing the participant's name and DID, see [section 4.3](#44-create-participants)
for details.

In practice, the provisioner agent will create the following resources for each participant:

- a control plane: this is the connector's DSP endpoint that handles contract negotiations etc.
- a data plane: this is a (trivial) http data plane to transmit example data
- an IdentityHub: this is the credential storage and DCP implementation
- dependencies like a PostgreSQL database and a Vault for secret storage.

In addition, the provisioner agent also pre-configures each participant with demo data:

- assets, policies, and contract definitions
- an account in its IdentityHub, so that the participant may present its credentials to other participants
- an account on the IssuerService, so that the participant may request credentials to be issued

**Asynchronous operation**: Provisioning participant data may take some time, depending on physical hardware and network
layout. Currently, the only way to get
notified when a deployment is ready is to inspect the logs of the provisioner. In production scenarios, that would
likely be handled using an eventing system.

**Multi-tenancy**: In the current PoC, multi-tenancy is implemented by creating a separate Kubernetes namespace for each
participant. In production scenarios, this will likely be different.

_The provisioning agent's source code can be found
in [this GitHub repository](https://github.com/Metaform/fulcrum-provisioner)._

#### 5.1.3 Credential types

In this PoC there are two types of credentials: a `MembershipCredential`, which attests to a participant being an active
member of the dataspace, and a
`DataProcessorCredential`, which attests to a participant's access level - either `"processing"` or `"sensitive"`.

When issuing a `MembershipCredential`, the `MembershipAttestationSource` creates the following credential subject:

```json
{
  "membershipStartDate": "<NOW>",
  "membershipType": "full-member",
  "id": "<PARTICIPANT_ID>"
}
```

When issuing a `DataProcessorCredential`, the `DataProcessorAttestationSource` creates the following credential subject:

```json
{
  "contractVersion": "1.0.0",
  "level": "processing",
  "id": "<PARTICIPANT_ID>"
}
```

These credentials are used to authenticate and authorize DSP/DCP requests from one connector to another. Each new
dataspace member will receive both
credentials.

### 5.2 Participant infrastructure

The participant infrastructure (shown in purple) is deployed for each participant by the Provisioner agent,
see [section 3.4](#44-create-participants) for
details. It includes a control plane, a data plane and an IdentityHub, plus dependencies like PostgreSQL and Vault.

They come pre-configured with some demo data (assets, policies, contract definitions) and an account in the IdentityHub
and the IssuerService.

## 6. References

| Reference                       | Link                                                                    | Used for                                                              |
|---------------------------------|-------------------------------------------------------------------------|-----------------------------------------------------------------------|
| Decentralized Claims Protocol   | <https://eclipse-dataspace-dcp.github.io/decentralized-claims-protocol> | Defines the protocol for presenting and issuing Verifiable Credentisl |
| Dataspace Protocol              | <https://eclipse-dataspace-protocol-base.github.io/DataspaceProtocol>   | Standard for data exchange and interoperability in dataspaces         |
| Decentralized Identifiers (DID) | <https://www.w3.org/TR/did-1.0/>                                        | Unique, verifiable digital identifiers                                |
| DID:web method                  | <https://w3c-ccg.github.io/did-method-web/>                             | Method for resolving DIDs using web infrastructure                    |
| Verifiable Credentials 2.0      | <https://www.w3.org/TR/vc-data-model/>                                  | Data model for digital credentials                                    |
