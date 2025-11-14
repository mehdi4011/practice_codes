use std::io::{stdin};

fn main() {
    for num in 1..=10 {
        // init
        println!("{}", num);
    }
    println!("_________________________________");
    let mut i = 10;
    while i >= 1 {
        println!("{}", i);
        i -= 1;
    }
    println!("_________________________________");
    let mut num = 1;
    loop {
        if num == 5 {
            num += 1;
            continue;
        } else if num == 8 {
            break;
        } else {
            println!("{num}");
        }
        num = num + 1;
    }
    //
    println!("_________________________________");
    let owner1 = String::from("Ibrahim");
    // let owner2 = owner1;
    // println!("{owner1}"); //eror due to ownership rules, value owner is being moved to borrower and cant be used out of scope
    let _borrower = &owner1;
    println!("{} {_borrower}", owner1.len());
    //
    println!("_________________________________");
    //closures..
    let closure = |x: i32| x + 2;
    println!("{:?}", closure(5));

    println!("_________________________________");
    //
    let vector = vec![1, 3, 5, 7, 78, 54];
    for vec in vector {
        println!("{vec}");
    }

    //
    println!("_________________________________");
    let mut input = String::new();
    println!("Enter a num");

    stdin().read_line(&mut input).expect("failed to read line");
    let num: i32 = input.trim().parse().expect("enter valid num");

    for i in 1..=10 {
        println!("{} x {} = {}", num, i, num * i);
    }

    //
    println!("_________________________________");
    let height = 5;
    for i in 1..=height {
        for _ in 0..i {
            print!("*");
        }
        println!()
    }

    //
    println!("_________________________________");

    for i in 1..=1000 {
        println!("{i}");
    }

    //
    println!("_________________________________");
    println!("");

    let calc = calculate(1, 5);
    println!("{calc}");
}

fn calculate(botton: i32, top: i32) -> i32 {
    (botton..=top).filter(|e| e % 2 == 0).sum()
}
