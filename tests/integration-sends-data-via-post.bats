#!/usr/bin/env bats

load './bats-helpers/bats-support/load'
load './bats-helpers/bats-assert/load'

setup() {
    UUID=$(uuidgen | awk '{print tolower($0)}')
    TOPIC=${UUID}-topic

    export LOGGER_FILENAME="${UUID}-logs.txt"
    ./target/debug/tiny-http-server & disown
    MOCK_PID=$!

    FILE=$(mktemp)
    cp ./tests/integration-sends-data-via-post.yaml $FILE

    CONNECTOR=${UUID}-sends-data
    export VERSION=$(cat ./crates/http-sink/Connector.toml | grep "^version = " | cut -d"\"" -f2)
    IPKG_NAME="http-sink-$VERSION.ipkg"
    fluvio topic create $TOPIC

    sed -i.BAK "s/CONNECTOR/${CONNECTOR}/g" $FILE
    sed -i.BAK "s/TOPIC/${TOPIC}/g" $FILE
    sed -i.BAK "s/VERSION/${VERSION}/g" $FILE
    cat $FILE

    cdk publish -p http-sink --pack --target x86_64-unknown-linux-musl
    cdk deploy -p http-sink start --config $FILE
}

teardown() {
    fluvio topic delete $TOPIC
    cdk deploy shutdown --name $CONNECTOR
    kill $MOCK_PID
}


@test "url_parameter" {
    echo "Starting consumer on topic $TOPIC"
    echo "Using connector $CONNECTOR"
    sleep 45
    
    echo "Produce \"{\"id\": 2901, \"name\": \"Luiz Barros Rocha\", \"age\": 26}\" on $TOPIC"
    echo "{\"id\": 2901, \"name\": \"Luiz Barros Rocha\", \"age\": 26}" | fluvio produce $TOPIC

    echo "Sleep to ensure record is processed"
    sleep 25

    echo ""
    
    cat ./$LOGGER_FILENAME | grep "url: \"/?condition=user_id+%3D+2901&age=26+years\""
    assert_success
}


@test "integration-sends-data-via-post" {
    echo "Starting consumer on topic $TOPIC"
    echo "Using connector $CONNECTOR"
    sleep 45

    echo "Produce \"California\" on $TOPIC"
    echo "California" | fluvio produce $TOPIC

    echo "Sleep to ensure record is processed"
    sleep 25

    echo "Contains California on Logger File"
    cat ./$LOGGER_FILENAME | grep "California"
    assert_success
}

@test "sends-user-agent-with-current-version" {
    echo "Starting consumer on topic $TOPIC"
    echo "Using connector $CONNECTOR"
    sleep 45

    echo "Produce \"North Carolina\" on $TOPIC"
    echo "North Carolina" | fluvio produce $TOPIC

    echo "Sleep to ensure record is processed"
    sleep 25

    echo "Contains User Agent with current version"
    cat ./$LOGGER_FILENAME | grep "user_agent: \"fluvio/http-sink $VERSION\""
    assert_success
}
