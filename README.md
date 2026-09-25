# setup

get an .env file which should have

```
ENDPOINT=<your-endpoint>
API_KEY=<the-api-key>
```

# tests description

## test-auth.sh

this one tests whether the auth works, for sanity. 
it pressumes you need the api key set, and will have a bunch of failures if your endpoint doesn't require a bearer token.

## test-server.sh 

This tests basic functionality of the server. health endpoint is tested along with the three possible querries laya (jev) supports.

## test-stress.sh 

this one is to see how much it can handle, it compares serieal and concurrent requests.
you can put in a number as an arguments to this script to set the number of concurrent requests it checks (i.e. `./test-stress.sh 10`)

## test-fan-out.sh 

This test how the server responds to multiple querries in a single curl request. 
Supposedly jev is able to bulk together requests in a single forward pass so this should perform better than serialise calls (or indeed concurrent curls).

## test-skill-routing.sh

this is like the previous test but tailored to an idea of how one might use system-one decision model in practice.
imagine an agent when given a request, first asks the system-one model whether each skill the model has is appropriate. 
the system-one model makes the choice (in under 200ms) and the skills are loaded into context.
Thus the LLM delegates responsibility of skill selection. pressumably this frees context because skills are only in context when actually loaded. 
In principle this extends to an infinite number of skills and context bloat never happens, you just wait for the system-one model a little bit more.

